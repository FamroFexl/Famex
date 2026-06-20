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

var orders_lock : util.Spinlock = .{.val = .init(false)};

var orders : [NUM_ORDERS + 1]OrderBlock = undefined;

const LocalPagePool = struct {
    current : u64,
    pages : util.data.Stack,
};

const local_page_pool = process.PerCpuStat(LocalPagePool);

pub fn orderToSize(order : anytype) usize {
    return @as(u64, types.SIZE_4KB) << @intCast(order);
}

pub fn sizeToOrder(size : usize) u8 {
    return 64 - @clz(size - 1) - 12;
}

// Initialize the page cache states
fn setupPageCache() void {
    print("  Initializing page cache\n", .{});

    for(0..cpu.FEATURES.NUM_CPU_CORES) |i| {
        const pool = local_page_pool.getGlobal(i);
        pool.current = 0;
        pool.pages.init();
    }
}

fn setupRegions() void {
    print("  Gathering usable memory regions\n", .{});

    var num_regions : u64 = 0;
    for (0..pmm.USABLE.len) |i| {
        const entry = pmm.USABLE[i];

        if(entry.region_end != entry.region_start) {
            const next = &pmm.USABLE[num_regions];
            next.* = entry;
            num_regions += 1;
        }
    }

    pmm.USABLE = pmm.USABLE[0..num_regions];
}

fn setupRegionOrders() void {
    print("  Filling page orders with first pages\n", .{});

    for (0..NUM_ORDERS) |i| {
        orders[i].free.init();
        orders[i].num_free = 0;
    }

    for (0..pmm.USABLE.len) |i| {
        const entry = pmm.USABLE[i];
        var cur : mem.Paddr = .{.val = entry.region_start};

        while (cur.val < entry.region_end) {
            const block_size : usize = bin.min(bin.maxAlignBetween(cur.val, entry.region_end), orderToSize(MAX_BUDDY_ORDER));

            const order = sizeToOrder(block_size);

            orders[order].free.insertFront(@ptrFromInt(cur.to_virt().val));
            orders[order].num_free += 1;

            cur.to_info().setData(.{
                .flags = .{.free = true,},
                .region = @intCast(i),
                .order = @intCast(order),
            });

            // Initialize all in-between pages in the block
            var page : mem.Paddr = .{.val = cur.val + types.SIZE_4KB};
            while (page.val < cur.val + block_size) : (page.val += types.SIZE_4KB) {
                page.to_info().setData(.{
                    .order = 0,
                    .region = @intCast(i),
                    .flags = @bitCast(@as(u8, 0)),
                });
            }

            cur.val += block_size;
        }
    }
}

pub fn __allocPage(order : u8) error{OrderEmpty}!mem.Paddr {    // No pages could be found in the order or in the ones above it
    util.locks.lockHeld(&orders_lock);

    log.apanic(order > MAX_BUDDY_ORDER, "Requested a buddy order larger than we have!\n", .{});

    var order_index : u8 = std.math.maxInt(u8);

    for(order..(MAX_BUDDY_ORDER + 1)) |i| {
        if (orders[i].num_free > 0) {
            order_index = @intCast(i);
            break;
        }
    }

    // No free blocks could be found
    if (order_index == std.math.maxInt(u8))
        return error.OrderEmpty;

    const block : mem.Vaddr = .{.val = @intFromPtr(orders[order_index].free.removeFront())};
    orders[order_index].num_free -= 1;

    const info = block.to_info();
    var data = info.getData();
    data.flags.free = false;
    data.order = @intCast(order);
    block.to_info().setData(data);
    info.setData(data);

    // Split the block and insert buddy blocks until the order is reached
    var i : i8 = @as(i8, @intCast(order_index)) - 1;
    while (i >= order) : (i -= 1) {
        const buddy : mem.Vaddr = .{.val = block.val ^ orderToSize(i)};
        const buddy_info = buddy.to_info();
        var buddy_data = buddy_info.getData();
        buddy_data.flags.free = true;
        buddy_data.order = @intCast(i);

        orders[@intCast(i)].free.insertFront(@ptrFromInt(buddy.val));
        orders[@intCast(i)].num_free += 1;
    }

    return block.to_phys();
}

pub fn __freePage(addr : mem.Paddr) void {
    util.locks.lockHeld(&orders_lock);

    var block = addr;
    var block_info = block.to_info();
    var block_data = block_info.getData();

    for (block_data.order..(MAX_BUDDY_ORDER + 1)) |i| {
        const size = orderToSize(block_data.order);

        const buddy : mem.Paddr = .{.val = addr.val ^ size};
        const buddy_info = buddy.to_info();
        const buddy_data = buddy_info.getData();
        const region = pmm.USABLE[buddy_data.region];

        if (buddy.val < region.region_start or
            buddy.val + size > region.region_end or
            buddy_data.flags.free == false or
            buddy_data.order != i) {
            break;
        }

        orders[buddy_data.order].free.remove(@ptrFromInt(buddy));

        // Set block to start of new block
        block.val &= ~size;

        block_info = block.to_info();
        block_data = block_info.getData();
        block_data.order += 1;
        block_info.setData(block_data);
    }

    block_data.flags.free = true;
    block_info.setData(block_data);
    orders[block_data.order].free.insertFront(@ptrFromInt(block.to_virt().val));
    orders[block_data.order].num_free += 1;
}

pub fn allocPage4k() mem.Paddr {
    //irq_save();

    const pool = local_page_pool.getLocal();

    var page : mem.Paddr = undefined;
    if(pool.current == 0) {
        orders_lock.lock();
        defer orders_lock.unlock();

        page = __allocPage(0) catch unreachable;
    }
    else {
        page = .{.val = @intFromPtr(pool.pages.pop())};
        pool.current -= 1;
    }

    //irq_restore

    return page;
}

// Adds a free page to the cache if the cache has space
pub fn freePage4k(addr : mem.Paddr) void {
    //irq_save();

    const pool = local_page_pool.getLocal();
    if (pool.current < config.PER_CPU_PAGE_NUM) {
        pool.pages.push(@ptrFromInt(addr.to_virt()));
        pool.current += 1;
    }
    else {
        orders_lock.lock();
        defer orders_lock.unlock();

        __freePage(addr);
    }

    //irq_restore
}

pub fn zallocPage4k() mem.Paddr {
    const page = allocPage4k();

    mem.memset(@ptrFromInt(page.to_virt().val), types.SIZE_4KB, 0);

    return page;
}

pub fn allocPage(order : u8) mem.Paddr {
    if (order == 0)
        return allocPage4k();

    var out : mem.Paddr = undefined;

    orders_lock.lock();
    defer orders_lock.unlock();

    out = __allocPage(order) catch unreachable;

    return out;
}

pub fn zallocPage(order : u8) mem.Paddr {
    if (order == 0)
        return zallocPage4k();

    const page = __allocPage(order);
    mem.memset(@ptrFromInt(page.to_virt()), orderToSize(order), 0);
    return page;
}

pub fn freePage(addr : mem.Paddr) void {
    if (addr.to_info().getData().order == 0) {
        freePage4k(addr);
        return;
    }

    orders_lock.lock();
    defer orders_lock.unlock();

    __freePage(addr);
}

pub fn setup() void {
    print("\nmm: Setting up Buddy Allocator:\n", .{});

    MAX_BUDDY_ORDER = @intCast(bin.max(config.MIN_BUDDY_ORDER, sizeToOrder(@as(usize, types.SIZE_4KB) << (@as(u6, cpu.FEATURES.MAX_PAGE_SIZE)*9))));

    setupPageCache();

    setupRegions();

    setupRegionOrders();
}