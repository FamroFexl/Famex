const kernel = @import("kernel");
const util = kernel.util;
const log = util.log;
const bin = util.binary;
const proc = kernel.pm.process;
const types = util.types;
const List = util.data.List;
const Stack = util.data.Stack;
const print = log.print;
const std = @import("std");
const builtin = @import("builtin");

const cpu = @import("arch").cpu;

const buddy = @import("buddy_alloc.zig");
const mem = @import("memory.zig");

pub var MAX_SLUB_ORDER : u8 = undefined;
pub var MAX_SLUB_SIZE : usize = undefined;

var slub_pool_pool : SlubPool = undefined;

pub var cacheline_pool : SlubPool = undefined;

pub var object_pools : [*]std.atomic.Value(?*SlubPool) = undefined;

const Slab = struct {
    link : List.Node,
    pool : *SlubPool,
    local_free : Stack,
    remote_free : util.data.AtomStack,

    inuse : std.atomic.Value(u16),    // Number of used objects
    frozen : std.atomic.Value(bool),  // Slab is in use by a CPU and cannot be moved to global lists
    full : std.atomic.Value(bool),    // Slab is full

    fn free(slab : *@This()) void {
        buddy.freePage(.{.val = @intFromPtr(slab)});
    }

    fn addRemoteFree(slab : *@This()) u64 {
        var node = slab.remote_free.drain();

        var count : u16 = 0;

        while (node != null) : (count += 1) {
            slab.local_free.push(@ptrCast(node));
            node = node.?.next.raw;
        }

        _ = slab.inuse.fetchSub(count, .seq_cst);

        return count;
    }

    pub fn remoteFreeObj(slab : *@This(), addr : mem.Vaddr) void {
        const pool = slab.pool;
        slab.remote_free.push(@ptrCast(@alignCast(addr.ptr())));
        const inuse : u16 = slab.inuse.fetchSub(1, .seq_cst) - 1;

        // Slab is empty, add to free list
        if (inuse == 0 and slab.frozen.load(.seq_cst)) {
            pool.spinlock.lock();

            pool.slabs_partial.remove(&slab.link);
            pool.slabs_empty.insertFront(&slab.link);

            // Max free slabs has been reached, release the LRU free slab
            if (pool.cur_slabs_empty == pool.max_slabs_empty) {
                const old_slab : *Slab = @fieldParentPtr("link", pool.slabs_empty.removeBack());

                pool.spinlock.unlock();
                old_slab.free();
            }
            else {
                pool.cur_slabs_empty += 1;
                    pool.spinlock.unlock();
            }
            return;
        }

        // Slab was full, set to partial
        if (slab.full.load(.seq_cst)) {
            pool.spinlock.lock();
            defer pool.spinlock.unlock();

            pool.slabs_full.remove(&slab.link);
            pool.slabs_partial.insertFront(&slab.link);
        }
    }

};

pub const SlubPool = struct {
    const SlabDyn = proc.PerCpuDyn(?*Slab);

    local_slab : SlabDyn,
    max_slabs_empty : u16,  // Max number of free slabs this pool can allocate
    cur_slabs_empty : u16,  // The current number of free slabs

    object_size : u32,      // Size of the object
    object_count : u16,     // Number of objects that can fit in the slab
    order : u8,             // Slab size in page orders
    alignment : u16,        // Object alignment

    slabs_full : List,      // List of full slabs
    slabs_partial : List,   // List of partially full slabs
    slabs_empty : List,     // List of empty slabs
    obj_init : *const fn (*anyopaque) void,

    spinlock : util.Spinlock,

    fn slubNoInit(none : *anyopaque) void {_ = none;}

    fn __init(pool : *@This(), size : anytype, alignment : anytype, order : anytype, count : anytype, obj_init : ?fn (*anyopaque) void) void {
        pool.object_size = @intCast(size);
        pool.order = order;
        pool.object_count = @intCast(count);
        pool.max_slabs_empty = 4;
        pool.cur_slabs_empty = 0;
        pool.alignment = @intCast(alignment);
        pool.spinlock.init();

        pool.obj_init = obj_init orelse slubNoInit;

        pool.slabs_full.init();
        pool.slabs_partial.init();
        pool.slabs_empty.init();

        pool.local_slab.alloc();
        for(0..cpu.FEATURES.NUM_CPU_CORES) |i| {
            pool.local_slab.getGlobal(i).* = null;
        }
    }

    pub fn init(pool : *@This(), size : usize, alignment : u16, obj_init : ?fn (*anyopaque) void) void {
        // We do not support less than minimum word size alignment
        const new_align = if (alignment < 8) 8 else bin.roundUpPow2(alignment);
        const size_aligned = bin.alignUp(size, new_align);

        const order = getSlubOrder(size_aligned, new_align);
        const block_size = buddy.orderToSize(order) - @sizeOf(Slab);
        var count = block_size / size_aligned;

        // Extra object can fit
        if (block_size % size_aligned >= size)
            count += 1;

        pool.__init(size, new_align, order, count, obj_init);
    }

    pub fn create(size : usize, alignment : u16, obj_init : ?fn (*anyopaque) void) *SlubPool {
        const pool : *SlubPool = slub_pool_pool.alloc();
        pool.init(size, alignment, obj_init);

        return pool;
    }

    fn allocSlab(pool : *@This()) *Slab {
        const pages = buddy.allocPage(pool.order);

        // Set orders for all pages so frees on the pages can find the slab
        var i : u64 = types.SIZE_4KB;
        while (i < buddy.orderToSize(pool.order)) : (i += types.SIZE_4KB) {
            const page : mem.Paddr = .{.val = pages.val + i};

            const info = page.toInfo();
            var info_data = info.getData();
            info_data.order = @intCast(pool.order);
            info.setData(info_data);
        }

        const slab : *Slab = @ptrCast(@alignCast(pages.toVirt().ptr()));
        slab.local_free.init();
        slab.remote_free.init();

        slab.inuse.raw = 0;
        slab.frozen.raw = false;
        slab.full.raw = false;
        slab.pool = pool;

        // Initialize all objects into the local free list
        const start : u64 = @intFromPtr(slab) + bin.alignUp(@sizeOf(Slab), pool.alignment);
        const incr = bin.alignUp(pool.object_size, pool.alignment);
        for(0..pool.object_count) |j| {
            const next_obj : *Stack.Node = @ptrFromInt(start + j * incr);
            slab.local_free.push(next_obj);
        }

        return slab;
    }

    pub fn getPool(addr : *anyopaque) *SlubPool {
        const vaddr : mem.Vaddr = .{.val = @intFromPtr(@as(*u64, @ptrCast(@alignCast(addr))))};
        const order = vaddr.toInfo().getData().order;
        const slab : *Slab = bin.castPtr(*Slab, @ptrFromInt(bin.alignDown(vaddr.val, buddy.orderToSize(order))));
        return slab.pool;
    }

    pub fn allocBulk(pool : *@This(), num : u64) Stack {
        proc.irqSave();

        var slab : *Slab = pool.local_slab.getLocal().* orelse blk: {
            const new_slab = allocSlab(pool);
            pool.local_slab.getLocal().* = new_slab;
            break :blk new_slab;
        };

        var stack : Stack = undefined;
        stack.init();

        var count : u64 = num;
        while (count > 0) {
            if (slab.local_free.empty() and slab.addRemoteFree() == 0)  {
                slab.frozen.store(false, .seq_cst);

                pool.spinlock.lock();

                // move cpu slab to slab_full
                slab.full.store(true, .seq_cst);
                pool.slabs_full.insertFront(&slab.link);

                if (!pool.slabs_partial.empty()) {
                    slab = @fieldParentPtr("link", pool.slabs_partial.removeFront());
                    pool.spinlock.unlock();
                }
                else if (!pool.slabs_empty.empty()) {
                    slab = @fieldParentPtr("link", pool.slabs_empty.removeFront());
                    pool.spinlock.unlock();
                }
                else {
                        pool.spinlock.unlock();
                    slab = pool.allocSlab();
                }

                slab.frozen.store(true, .seq_cst);
                // set cpu local slab to new slab
                pool.local_slab.getLocal().* = slab;
            }

            _ = slab.inuse.fetchAdd(1, .seq_cst);
            const obj = slab.local_free.pop().?;
            pool.obj_init(@ptrCast(obj));

            stack.push(obj);
            count -= 1;
        }

        proc.irqRestore();

        return stack;
    }

    pub fn alloc(pool : *@This()) *anyopaque {
        var stack = pool.allocBulk(1);
        return @ptrCast(stack.pop());
    }

    pub fn free(pool : *@This(), addr : *anyopaque) void {
        const new_addr : mem.Vaddr = .{.val = @intFromPtr(addr)};
        const info = new_addr.toInfo();
        const slab : *Slab = @ptrFromInt(bin.alignDown(new_addr.val, buddy.orderToSize(info.getData().order)));

        // Frees technically don't need knowledge of the pool, but like linked list delete, it is a form of documentation
        std.debug.assert(slab.pool == pool);

        // Local free
        if (slab == slab.pool.local_slab.getLocal().*) {
            slab.local_free.push(@ptrCast(@alignCast(new_addr.ptr())));
            _ = slab.inuse.fetchSub(1, .seq_cst);
        }
        // Remote free
        else {
            slab.remoteFreeObj(new_addr);
        }
    }

    pub fn freeBulk(pool : *@This(), stack : Stack) void {
        while (true) {
            const node = stack.pop orelse break;
            free(pool, node);
        }
    }
};

pub fn SlubPoolTyped(comptime T: type, obj_init : ?fn (*anyopaque) void) type {
    const new_pool = SlubPool.create(@sizeOf(type), @alignOf(type), obj_init);
    return struct {
        pool : *SlubPool = new_pool,

        pub fn allocBulk(typed : *@This(), num : u64) Stack {
            return typed.pool.allocBulk(num);
        }

        pub fn alloc(typed : *@This()) *T {
            return @ptrCast(typed.pool.alloc());
        }

        pub fn free(typed : *@This(), addr : *T) void {
            typed.pool.free(typed.pool, addr);
        }

        pub fn freeBulk(typed : *@This(), stack : Stack) void {
            typed.pool.freeBulk(typed.pool, stack);
        }
    };
}

// Setup the array mapping sizes to pools
fn setupObjectArray() void {
    print("  Setting up the PMalloc pool object array\n", .{});

    const order = buddy.sizeToOrder(MAX_SLUB_SIZE);
    const vaddr : mem.Vaddr = buddy.allocPage(order).toVirt();
    mem.memset(@ptrFromInt(vaddr.val), buddy.orderToSize(order), 0);

    object_pools = @ptrFromInt(vaddr.val);
}

fn getSlubOrder(size : anytype, alignment : anytype) u8 {
    const new_size = bin.alignUp(size, alignment);
    const mdata = bin.alignUp(@sizeOf(Slab), alignment);

    var min_order : u8 = 0;

    while (new_size + mdata > buddy.orderToSize(min_order)) {
        min_order += 1;
    }

    var best_ratio : u64 = std.math.maxInt(u64);
    var out_order : u8 = min_order;

    const scaling = 10000;
    for (min_order..(MAX_SLUB_ORDER + 1)) |i| {
        const count : u64 = (buddy.orderToSize(i) - mdata) / new_size;
        const waste : u64 = buddy.orderToSize(i) - mdata - count * new_size;

        // Order selection behavior
        const per_obj_waste = (waste*scaling + count/2) / count;
        const order_weight : u64 = (@as(u64, 1) << (@as(u6, @intCast(i))*2)) * scaling;
        const comp_ratio = per_obj_waste + order_weight;

        if (comp_ratio < best_ratio) {
            best_ratio = comp_ratio;
            out_order = @intCast(i);
        }
    }

    return out_order;
}


// Setup the pool for allocating SlubPool objects
fn setupSlubPoolPool() void {
    print("  Setting up the pool for allocating slub pools\n", .{});

    const size = @sizeOf(SlubPool);
    slub_pool_pool.init(size, 8, null);

    // Setup the main list
    var i : i64 = size >> 3;
    while (i >= 0) : (i -= 1) {
        const cur_pool = object_pools[@intCast(i)].load(.acquire);
        if (cur_pool == null or cur_pool.?.object_size >> 3 != i) {
            object_pools[@intCast(i)].store(&slub_pool_pool, .release);
        }
        else {
            break;
        }
    }
}

fn slubPoolPmalloc(size : u64) void {
    var aligned_8 = bin.alignUp(size, 8);

    const order = getSlubOrder(aligned_8, 8);
    const block_size = buddy.orderToSize(order) - @sizeOf(Slab);
    var count = block_size / aligned_8;

    // Extra object can fit
    if (block_size % aligned_8 >= size) {
        count += 1;
    }

    // Get the largest size that guarantees the same order and count
    aligned_8 = bin.alignDown(block_size / count, 8);

    const shift_8 = aligned_8 >> 3;

    // Pool has already been created
    const pool = object_pools[shift_8].load(.unordered);
    if (pool != null and pool.?.object_size == aligned_8)
        return;

    const new_pool = bin.castPtr(*SlubPool, slub_pool_pool.alloc());
    new_pool.__init(aligned_8, 8, order, count, null);

    // Initialize pool in object array
    var i : i64 = @as(i64, @intCast(size)) >> 3;
    while (i >= 0) : (i -= 1) {
        const cur_pool = object_pools[@intCast(i)].load(.acquire);
        if (cur_pool == null or cur_pool.?.object_size >> 3 != i) {
            object_pools[@intCast(i)].store(&slub_pool_pool, .release);
        }
        else {
            break;
        }
    }
}

/// Setup the first pools to ensure all allocations up to MAX_SLUB_SIZE can occur before other
/// systems have the opportunity to setup their own pools.
fn setupPow2Pools() void {
    print("  Setting up first power-of-2 pools for PMalloc\n", .{});

    var i : u32 = 8;
    while (i < MAX_SLUB_SIZE) : (i *= 2) {
        slubPoolPmalloc(i);
    }

    slubPoolPmalloc(96);
    slubPoolPmalloc(192);
    slubPoolPmalloc(384);

    // This ensures that no entries in the object array are invalid and will point to a valid slub pool
    slubPoolPmalloc(MAX_SLUB_SIZE);
}

pub fn setup() void {
    print("\nmm: Setting up Slub Allocator:\n", .{});
    MAX_SLUB_ORDER = @intCast(bin.min(buddy.MAX_BUDDY_ORDER, 3));
    MAX_SLUB_SIZE = (buddy.orderToSize(MAX_SLUB_ORDER) - @sizeOf(Slab)) / 2;

    setupObjectArray();

    setupSlubPoolPool();

    setupPow2Pools();

    cacheline_pool.init(cpu.FEATURES.CACHELINE_SIZE, cpu.FEATURES.CACHELINE_SIZE, null);
}