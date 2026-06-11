const std = @import("std");

const kernel = @import("kernel");
const util = kernel.util;
const bin = util.binary;
const config = kernel.config;
const types = util.types;
const process = kernel.pm.process;
const log = util.log;
const print = log.print;

const cpu = @import("arch").cpu;

const pmm = @import("pmm.zig");
const mem = @import("memory.zig");
const paging = @import("paging.zig");

const NUM_ORDERS = 18;

pub var MAX_BUDDY_ORDER : u8 = undefined;

const OrderBlock = struct {
    free : util.data.List,
    num_free : u64,
};

var orders_lock : util.Spinlock = false;

var orders : [NUM_ORDERS]OrderBlock = undefined;

const LocalPagePool = struct {
    current : u64,
    pages : util.data.Stack,
};

const local_page_pool = process.PerCpuStat(LocalPagePool);

pub fn order_to_size(order : anytype) usize {
    return @as(u64, types.SIZE_4KB) << @intCast(order);
}

pub fn size_to_order(size : usize) u64 {
    return 64 - @clz(size - 1) - 12;
}

// Initialize the page cache states
fn setup_page_cache() void {
    for(0..cpu.FEATURES.NUM_CPU_CORES) |i| {
        const pool = local_page_pool.get_global(i);
        pool.current = 0;
        pool.pages.init();
    }
}

fn setup_regions() void {
    var num_regions : u64 = 0;
    for (0..pmm.USABLE.len) |i| {
        const entry = pmm.USABLE[i];

        if(entry.region_end != entry.region_start) {
            num_regions += 1;
            const next = &pmm.USABLE[num_regions];
            next.* = entry;
        }
    }

    pmm.USABLE = pmm.USABLE[0..num_regions];
}

fn setup_region_orders() void {
    for (0..NUM_ORDERS) |i| {
        orders[i].free.init();
        orders[i].num_free = 0;
    }

    for (0..pmm.USABLE.len) |i| {
        const entry = pmm.USABLE[i];
        var cur : mem.Paddr = .{.val = entry.block_start};

        while (cur.val < entry.block_end) {
            const block_size : usize = bin.min(bin.max_align_between(cur.val, entry.block_end), order_to_size(MAX_BUDDY_ORDER));

            const order = size_to_order(block_size);

            orders[order].free.insert_front(@ptrFromInt(cur.to_virt().val));
            orders[order].num_free += 1;

            cur.to_info().set_data(.{
                .flags = .{.free = true,},
                .region = @intCast(i),
                .order = @intCast(order),
            });

            // Initialize all in-between pages in the block
            var page : mem.Paddr = .{.val = cur.val + types.SIZE_4KB};
            while (page.val < cur.val + block_size) : (page.val += types.SIZE_4KB) {
                page.to_info().set_data(.{
                    .order = 0,
                    .region = @intCast(i),
                    .flags = @bitCast(@as(u8, 0)),
                });
            }

            cur.val += block_size;
        }
    }
}

pub const PageAllocError = error {
    OrderEmpty,  // No pages could be found in the order or in the ones above it
};

pub fn __alloc_page(order : u8) !mem.Paddr {
    util.locks.lock_held(&orders_lock);

    log.apanic(order > MAX_BUDDY_ORDER, "Requested a buddy order larger than we have!\n", .{});

    var order_index : u8 = std.math.maxInt(u8);

    for(order..(MAX_BUDDY_ORDER + 1)) |i| {
        if (orders[i].cur > 0) {
            order_index = i;
            break;
        }
    }

    // No free blocks could be found
    if (order_index == std.math.maxInt(u8))
        return PageAllocError.OrderEmpty;

    const block : mem.Vaddr = .{.val = @intFromPtr(orders[order_index].free.remove_front())};
    orders[order_index].num_free -= 1;

    const info = block.to_info();
    var data = info.get_data();
    data.flags.free = false;
    data.order = order;
    block.to_info().set_data(data);
    info.set_data(data);

    // Split the block and insert buddy blocks until the order is reached
    var i : i8 = order_index - 1;
    while (i >= order) : (i -= 1) {
        const buddy : mem.Vaddr = .{.val = block.val ^ order_to_size(i)};
        const buddy_info = buddy.to_info();
        var buddy_data = buddy_info.get_data();
        buddy_data.flags.free = true;
        buddy_data.order = @intCast(i);

        orders[i].free.insert_front(@ptrFromInt(buddy));
        orders[i].num_free += 1;
    }

    return block.to_phys();
}

pub fn __free_page(addr : mem.Paddr) void {
    util.locks.lock_held(&orders_lock);

    var block = addr;
    var block_info = block.to_info();
    var block_data = block_info.get_data();

    for (block_data.order..(MAX_BUDDY_ORDER + 1)) |i| {
        const size = order_to_size(block_data.order);

        const buddy : mem.Paddr = .{.val = addr.val ^ size};
        const buddy_info = buddy.to_info();
        const buddy_data = buddy_info.get_data();
        const region = pmm.USABLE[buddy_data.region];

        if (buddy.val < region.block_start or
            buddy.val + size > region.block_end or
            buddy_data.flags.free == false or
            buddy_data.order != i) {
            break;
        }

        orders[buddy_data.order].free.remove(@ptrFromInt(buddy));

        // Set block to start of new block
        block.val &= ~size;

        block_info = block.to_info();
        block_data = block_info.get_data();
        block_data.order += 1;
        block_info.set_data(block_data);
    }

    block_data.flags.free = true;
    block_info.set_data(block_data);
    orders[block_data.order].free.insert_front(@ptrFromInt(block.to_virt().val));
    orders[block_data.order].num_free += 1;
}

pub fn alloc_page_4k() mem.Paddr {
    //irq_save();

    const pool = local_page_pool.get_local();

    var page = undefined;
    if(pool.current == 0) {
        orders_lock.lock();
        defer orders_lock.unlock();

        page = __alloc_page(0);
    }
    else {
        page = .{.val = @intFromPtr(pool.pages.pop())};
        pool.current -= 1;
    }

    //irq_restore

    return page;
}

// Adds a free page to the cache if the cache has space
pub fn free_page_4k(addr : mem.Paddr) void {
    //irq_save();

    const pool = local_page_pool.get_local();
    if (pool.current < config.PER_CPU_PAGE_NUM) {
        pool.pages.push(@ptrFromInt(addr.to_virt()));
        pool.current += 1;
    }
    else {
        orders_lock.lock();
        defer orders_lock.unlock();

        __free_page(addr);
    }

    //irq_restore
}

pub fn zalloc_page_4k() mem.Paddr {
    const page = alloc_page_4k();

    mem.memset(@ptrFromInt(page.to_virt()), types.SIZE_4KB, 0);

    return page;
}

pub fn alloc_page(order : u8) mem.Paddr {
    if (order == 0)
        return alloc_page_4k();

    const out = undefined;

    orders_lock.lock();
    defer orders_lock.unlock();

    out = __alloc_page(order);

    return out;
}

pub fn zalloc_page(order : u8) mem.Paddr {
    if (order == 0)
        return zalloc_page_4k();

    const page = __alloc_page(order);
    mem.memset(@ptrFromInt(page.to_virt()), order_to_size(order), 0);
    return page;
}

pub fn free_page(addr : mem.Paddr) void {
    if (addr.to_info().get_data().order == 0) {
        free_page_4k(addr);
        return;
    }

    orders_lock.lock();
    defer orders_lock.unlock();

    __free_page(addr);
}

pub fn setup() void {
    print("\nmm: Setting up Buddy Allocator:\n", .{});

    MAX_BUDDY_ORDER = @intCast(bin.max(config.MIN_BUDDY_ORDER, size_to_order(@as(usize, types.SIZE_4KB) << (@as(u6, cpu.FEATURES.MAX_PAGE_SIZE)*9))));

    print("  Initializing page cache\n", .{});
    setup_page_cache();

    print("  Gathering usable memory regions\n", .{});
    setup_regions();

    print("  Filling page orders with first pages\n", .{});
    setup_region_orders();
}