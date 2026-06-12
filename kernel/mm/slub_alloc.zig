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
const AtomicOrder = std.builtin.AtomicOrder;
const AtomicRmwOp = std.builtin.AtomicRmwOp;

const cpu = @import("arch").cpu;

const buddy = @import("buddy_alloc.zig");
const mem = @import("memory.zig");

const Slab = struct {
    link : List.Node,
    pool : *SlubPool,
    local_free : Stack,
    remote_free : util.data.AtomStack,

    inuse : u16,    // Number of used objects
    flags : Flags,

    const Flags = packed struct(u16) {
        frozen : bool,  // Slab is in use by a CPU and cannot be moved to global lists
        full : bool,    // Slab is full
        pad : u14,
    };

    fn free(slab : *@This()) void {
        buddy.free_page(.{.val = @intFromPtr(slab)});
    }

    fn add_remote_free(slab : *@This()) u64 {
        //atomic
        var node = slab.remote_free.drain();
        var count : u64 = 0;

        while (node != null) : (count += 1) {
            slab.local_free.push(node);
            node = node.next;
        }

        // atomic
        @atomicRmw(u16, &slab.inuse, AtomicRmwOp.Sub, count, AtomicOrder.seq_cst);

        return count;
    }

    pub fn remote_free_obj(slab : *@This(), addr : mem.Vaddr) void {
        const pool = slab.pool;
        slab.remote_free.push(addr.ptr());
        const inuse : u16 = @atomicRmw(u16, &slab.inuse, AtomicRmwOp.Sub, 1, AtomicOrder.seq_cst) - 1;

        // Slab is empty, add to free list
        if (inuse == 0 and @atomicLoad(bool, &slab.flags.frozen, AtomicOrder.seq_cst)) {
            pool.spinlock.lock();

            pool.slabs_partial.remove(&slab.link);
            pool.slabs_empty.insert_front(&slab.link);

            // Max free slabs has been reached, release the LRU free slab
            if (pool.cur_slabs_empty == pool.max_slabs_empty) {
                const old_slab : *Slab = @fieldParentPtr("link", pool.slabs_empty.remove_back());

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
        if (@atomicLoad(bool, slab.flags.full, AtomicOrder.seq_cst)) {
            pool.spinlock.lock();
            defer pool.spinlock.unlock();

            pool.slabs_full.remove(&slab.link);
            pool.slabs_partial.insert_front(&slab.link);
        }
    }

};

const SlubPool = struct {
    const SlabDyn = proc.PerCpuDyn(*Slab);

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
    obj_init : fn (*anyopaque) void,

    spinlock : util.Spinlock,

    fn slub_no_init(none : *anyopaque) void {_ = none;}

    pub fn init(pool : *@This(), size : anytype, alignment : anytype, order : anytype, count : anytype, obj_init : ?fn (*anyopaque) void) void {
        pool = .{
            .object_size = size,
            .order = order,
            .object_count = count,
            .max_slabs_empty = 4,
            .cur_slabs_empty = 0,
            .alignment = alignment,
            .obj_init = if (obj_init == null) slub_no_init else obj_init,
            .spinlock = false,
        };

        pool.slabs_full.init();
        pool.slabs_partial.init();
        pool.slabs_empty.init();

        pool.local_slab.alloc();
        for(0..cpu.FEATURES.NUM_CPU_CORES) |i| {
            pool.local_slab.get_global(i).* = null;
        }
    }

    pub fn create(size : usize, alignment : u16, obj_init : ?fn (*anyopaque) void) *SlubPool {
        // We do not support less than minimum word size alignment
        const new_align = if (alignment < 8) 8 else bin.round_up_pow2(alignment);
        const size_aligned = bin.align_up(size, new_align);

        const order = get_slub_order(size_aligned, new_align);
        const block_size = buddy.order_to_size(order) - @sizeOf(Slab);
        const count = block_size / size_aligned;

        // Extra object can fit
        if (block_size % size_aligned >= size)
            count += 1;

        const pool : *SlubPool = slub_pool_pool.alloc();
        pool.init(size, new_align, order, count, obj_init);

        return pool;
    }

    fn alloc_slab(pool : *@This()) *Slab {
        const pages = buddy.alloc_page(pool.order);
        log.apanic(pages == null, "Pmalloc couldn't satisfy SLUB request for page order {} (", .{pool.order});

        // Set orders for all pages so frees on the pages can find the slab
        var i : u64 = types.SIZE_4KB;
        while (i < buddy.order_to_size(pool.order)) : (i += types.SIZE_4KB) {
            const page = @as(mem.Vaddr, @ptrFromInt(pages.val + i));

            const info = page.to_info();
            const info_data = info.get_data();
            info_data.order = pool.order;
            info.set_data(info_data);
        }

        const slab : *Slab = pages.to_virt().ptr();
        slab.local_free.init();
        slab.remote_free.init();

        slab.inuse = 0;
        slab.flags = 0;
        slab.pool = pool;

        // Initialize all objects into the local free list
        const start : u64 = .{.val = @intFromPtr(slab) + bin.align_up(@sizeOf(Slab), pool.alignment)};
        const incr = bin.align_up(pool.object_size, pool.alignment);
        for(0..pool.object_count) |j| {
            const next_obj : *Stack.Node = @ptrFromInt(start + j * incr);
            slab.local_free.push(next_obj);
        }

        return slab;
    }

    pub fn alloc_bulk(pool : *@This(), num : u64) Stack {
        // irq_save();

        var slab : *Slab = pool.local_slab.get_local().*;
        if (slab == null) {
            slab = alloc_slab(pool);
            pool.local_slab.get_local().* = slab;
        }

        var stack = Stack;
        stack.init();

        var count : u64 = num;
        while (count > 0) {
            if (slab.local_free.empty() and slab.add_remote_free() == 0)  {
                @atomicStore(bool, &slab.flags.frozen, 0, AtomicOrder.seq_cst);

                pool.spinlock.lock();

                // move cpu slab to slab_full
                pool.slabs_full.insert_front(slab.link);

                if (!pool.slabs_partial.empty()) {
                    slab = @fieldParentPtr("link", pool.slabs_partial.remove_front());
                    pool.spinlock.unlock();
                }
                else if (!pool.slabs_empty.empty()) {
                    slab = @fieldParentPtr("link", pool.slabs_empty.remove_front());
                    pool.spinlock.unlock();
                }
                else {
                        pool.spinlock.unlock();
                    slab = pool.alloc_slab();
                }

                @atomicStore(bool, &slab.flags.frozen, 1, AtomicOrder.seq_cst);
                // set cpu local slab to new slab
                pool.local_slab.get_local().* = slab;
            }

            @atomicRmw(u16, &slab.inuse, AtomicRmwOp.Add, 1, AtomicOrder.seq_cst);
            const obj = slab.local_free.pop();
            pool.obj_init(@ptrCast(obj));

            stack.push(obj);
            count -= 1;
        }

        // irq_restore();

        return stack;
    }

    pub fn alloc(pool : *@This()) *anyopaque {
        const stack = pool.alloc_bulk(1);
        return stack.pop();
    }

    pub fn free(pool : *@This(), addr : *anyopaque) void {
        const new_addr : mem.Vaddr = .{.val = @intFromPtr(addr)};
        const info = addr.to_info();
        const slab : *Slab = @ptrFromInt(bin.align_down(new_addr, buddy.order_to_size(info.get_data().order)));

        if (builtin.mode == .Debug) {
            log.apanic(slab.pool != pool, "A free was requested on the wrong SLUB pool!\n", .{});
        }

        // Local free
        if (slab == slab.pool.local_slab.get_local().*) {
            slab.local_free.push(new_addr.ptr());
            @atomicRmw(u16, &slab.inuse, AtomicRmwOp.Sub, 1, AtomicOrder.seq_cst);
        }
        // Remote free
        else {
            slab.remote_free_obj(new_addr);
        }
    }

    pub fn free_bulk(pool : *@This(), stack : Stack) void {
        var node : *Stack.Node = stack.pop();
        while (node) : (node = stack.pop()) {
            free(pool, node);
        }
    }
};

pub fn SlubPoolTyped(comptime T: type, obj_init : ?fn (*anyopaque) void) type {
    const new_pool = SlubPool.create(@sizeOf(type), @alignOf(type), obj_init);
    return struct {
        pool : *SlubPool = new_pool,

        pub fn alloc_bulk(typed : *@This(), num : u64) Stack {
            return typed.pool.alloc_bulk(num);
        }

        pub fn alloc(typed : *@This()) *T {
            return @ptrCast(typed.pool.alloc());
        }

        pub fn free(typed : *@This(), addr : *T) void {
            typed.pool.free(typed.pool, addr);
        }

        pub fn free_bulk(typed : *@This(), stack : Stack) void {
            typed.pool.free_bulk(typed.pool, stack);
        }
    };
}

var MAX_SLUB_ORDER : u8 = undefined;
var MAX_SLUB_SIZE : usize = undefined;

var slub_pool_pool : SlubPool = undefined;

var cacheline_pool : SlubPool = undefined;

var object_pools : [*]*SlubPool = undefined;

// Setup the array mapping sizes to pools
fn setup_object_array() void {
    const order = buddy.size_to_order(MAX_SLUB_SIZE);
    const vaddr : mem.Vaddr = buddy.alloc_page(order).to_virt();
    mem.memset(@ptrFromInt(vaddr.val), buddy.order_to_size(order), 0);

    object_pools = @ptrFromInt(vaddr.val);
}

fn get_slub_order(size : anytype, alignment : anytype) u8 {
    const new_size = bin.align_up(size, alignment);
    const mdata = bin.align_up(@sizeOf(Slab), alignment);

    var min_order : u8 = 0;

    while (new_size + mdata > buddy.order_to_size(min_order)) {
        min_order += 1;
    }

    var best_ratio : u64 = std.math.maxInt(u64);
    var out_order : u8 = min_order;

    const scaling = 10000;
    for (min_order..(MAX_SLUB_ORDER + 1)) |i| {
        const count : u64 = (buddy.order_to_size(i) - mdata) / new_size;
        const waste : u64 = buddy.order_to_size(i) - mdata - count * new_size;

        // Order selection behavior
        const per_obj_waste = (waste*scaling + count/2) / count;
        const order_weight = (1 << i*2) * scaling;
        const comp_ratio = per_obj_waste + order_weight;

        if (comp_ratio < best_ratio) {
            best_ratio = comp_ratio;
            out_order = i;
        }
    }

    return out_order;
}


// Setup the pool for allocating SlubPool objects
fn setup_slub_pool_pool() void {
    const size = @sizeOf(SlubPool);
    const order = get_slub_order(size, 8);
    const count = (buddy.order_to_size(order) - @sizeOf(Slab)) / size;

    slub_pool_pool.init(size, 8, order, count, null);

    // Setup the main list
    var i : i64 = size >> 3;
    while (i >= 0) : (i -= 1) {
        const cur_pool = @atomicLoad(*SlubPool, &object_pools[i], AtomicOrder.acquire);
        if (cur_pool == null or cur_pool.object_size >> 3 != i) {
            @atomicStore(*SlubPool, &object_pools[i], slub_pool_pool, AtomicOrder.release);
        }
        else {
            break;
        }
    }
}

fn slub_pool_pmalloc(size : u64) void {
    var aligned_8 = bin.align_up(size, 8);

    const order = get_slub_order(aligned_8, 8);
    const block_size = buddy.order_to_size(order) - @sizeOf(Slab);
    const count = block_size / aligned_8;

    // Extra object can fit
    if (block_size % aligned_8 >= size) {
        count += 1;
    }

    // Get the largest size that guarantees the same order and count
    aligned_8 = bin.align_down(block_size / count, 8);

    const shift_8 = aligned_8 >> 3;

    // Pool has already been created
    const pool = @atomicLoad(*SlubPool, &object_pools[shift_8], AtomicOrder.unordered);
    if (pool != null and pool.object_size == aligned_8)
        return;

    const new_pool : *SlubPool = slub_pool_pool.alloc();
    new_pool.init(aligned_8, 8, order, count, null);

    // Initialize pool in object array
    var i : i64 = size >> 3;
    while (i >= 0) : (i -= 1) {
        const cur_pool = @atomicLoad(*SlubPool, &object_pools[i], AtomicOrder.acquire);
        if (cur_pool == null or cur_pool.object_size >> 3 != i) {
            @atomicStore(*SlubPool, &object_pools[i], slub_pool_pool, AtomicOrder.release);
        }
        else {
            break;
        }
    }
}

/// Setup the first pools to ensure all allocations up to MAX_SLUB_SIZE can occur before other
/// systems have the opportunity to setup their own pools.
fn setup_pow2_pools() void {
    var i : u32 = 8;
    while (i < MAX_SLUB_SIZE) : (i *= 2) {
        slub_pool_pmalloc(i);
    }

    slub_pool_pmalloc(96);
    slub_pool_pmalloc(192);
    slub_pool_pmalloc(384);

    // This ensures that no entries in the object array are invalid and will point to a valid slub pool
    slub_pool_pmalloc(MAX_SLUB_SIZE);
}

fn setup() void {
    print("\nmm: Setting up Slub Allocator:\n", .{});
    MAX_SLUB_ORDER = bin.min(buddy.MAX_BUDDY_ORDER, 3);
    MAX_SLUB_SIZE = (buddy.order_to_size(MAX_SLUB_ORDER) - @sizeOf(Slab)) / 2;

    print("  Setting up the PMalloc pool object array\n", .{});
    setup_object_array();

    print("  Setting up the pool for allocating slub pools\n", .{});
    setup_slub_pool_pool();

    print("  Setting up first power-of-2 pools for PMalloc\n", .{});
    setup_pow2_pools();

    cacheline_pool = SlubPool.create(cpu.FEATURES.CACHELINE_SIZE, cpu.FEATURES.CACHELINE_SIZE, null);
}