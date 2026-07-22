const std = @import("std");

const lib = @import("lib");

const kernel = @import("kernel");
const cast = kernel.cast;
const print = kernel.util.log.print;
const bin = kernel.util.binary;
const types = kernel.util.types;

const cpu = @import("arch").cpu;

const paging = @import("paging.zig");
const pmm = @import("pmm.zig");
const vmm = @import("vmm.zig");
const slub = @import("slubAlloc.zig");
const buddy = @import("buddyAlloc.zig");

pub const Addr = u64;

pub const Paddr = struct {
    val : u64,

    pub fn asPhys(num : u64) Paddr {
        return .{.val = num};
    }

    pub fn toVirt(this : @This()) Vaddr {
        return .{.val = this.val + PAGE_OFFSET.val};
    }

    pub fn toInfo(this : @This()) *paging.PageInfo {
        return @ptrFromInt(PAGE_METADATA.val + ((this.val / types.SIZE_4KB) * @sizeOf(paging.PageInfo)));
    }

    pub fn ptr(this : @This()) *anyopaque {
        return @ptrFromInt(this.val);
    }
};

pub const Vaddr = struct {
    val : u64,

    pub fn asVirt(num : u64) Vaddr {
        return .{.val = num};
    }

    pub fn toPhys(this : @This()) Paddr {
        return .{.val = this.val - PAGE_OFFSET.val};
    }

    pub fn toInfo(this : @This()) *paging.PageInfo {
        return this.toPhys().toInfo();
    }

    pub fn ptr(this : @This()) *anyopaque {
        return @ptrFromInt(this.val);
    }
};

pub var PHYS_ADDR_SIZE : u64 = undefined;

pub var VIRT_ADDR_SIZE : u64 = undefined;

pub var PAGE_OFFSET_SIZE : usize = undefined;
pub var KERNEL_ALLOC_SIZE : usize = undefined;
pub var PAGE_METADATA_SIZE : usize = undefined;
pub const PER_CPU_DATA_SIZE : usize = types.SIZE_32MB;

pub var PAGE_OFFSET : Vaddr = undefined;
pub const USER_MEMORY_START : Vaddr = .asVirt(0x1000);
pub var USER_MEMORY_END : Vaddr = undefined;
pub var KERNEL_MEMORY_START : Vaddr = undefined;
pub var KERNEL_MEMORY : Vaddr = undefined;
pub var KERNEL_ALLOC : Vaddr = undefined;
pub var PAGE_METADATA : Vaddr = undefined;
pub var PER_CPU_DATA : Vaddr = undefined;

pub const KERNEL_IMAGE : Vaddr = .{.val = 0xFFFFFFFF80000000};
pub const MODULE_IMAGES : Vaddr = .{.val =0xFFFFFFFFA0000000};

/// raw @memset usage is way too finicky to get right
pub fn memset(ptr : *anyopaque, size : anytype, val : u8) void {
    const bytes : [*]u8 = @ptrCast(ptr);
    @memset(bytes[0..size], val);
}

pub fn memcpy(dest : *anyopaque, src : *anyopaque, size : anytype) void {
    const destBytes : [*]u8 = @ptrCast(dest);
    const srcBytes : [*]u8 = @ptrCast(src);
    @memcpy(destBytes[0..size], srcBytes[0..size]);
}

pub fn pmallocBytes(size : usize) *anyopaque {
    // Size is larger than max slub size
    if (size > slub.MAX_SLUB_SIZE) {
        return buddy.allocPage(@intCast(buddy.sizeToOrder(size))).toVirt().ptr();
    }

    return slub.SlubPool.alloc(slub.object_pools[size >> 3].load(.acquire).?);
}

pub fn pmalloc(comptime T: type) *T {
    std.debug.assert(@alignOf(T) <= 8);

    return @ptrCast(@alignCast(pmallocBytes(@sizeOf(T))));
}

pub fn pfreeBytes(addr : *anyopaque) void {
    // Is a page, not a slub object
    const vaddr : Vaddr = .asVirt(@intFromPtr(addr));
    const info = vaddr.toInfo();
    if (bin.alignDown(vaddr.val, buddy.orderToSize(info.getData().order)) == vaddr.val) {
        buddy.freePage(vaddr.toPhys());
        return;
    }

    slub.SlubPool.free(addr);
}

pub fn pfree(comptime T: type, addr : *T) void {
    pfreeBytes(addr);
}

pub fn vmallocBytes(size : usize) *anyopaque {
    const aligned = bin.alignUp(size, types.SIZE_4KB);

    const area = pmalloc(vmm.VmArea);
    area.areaType = .VMALLOC;
    area.flags = .{
        .read = true,
        .write = true,
        .exec = true,
    };

    const vmSpace = &kernel.kernelProcess.addrSpace;

    var mas = lib.linux.MapleTree.MaState.create(&vmSpace.tree, 0, 0);
    mas.lock();

    mas.emptyArea(vmSpace.start.val, vmSpace.end.val, aligned);

    area.start = .asVirt(mas.val.index);
    area.end = .asVirt(area.start.val + aligned);

    mas.setRange(area.start.val, area.end.val - 1);
    mas.store(area);

    mas.unlock();

    // Page mapping
    var pfeState = kernel.PfeState(.MAP).create(vmSpace, area.start, area.end, .LEVEL_4KB);

    vmSpace.spinlock.lock();
    defer vmSpace.spinlock.unlock();

    while (pfeState.next()) |pfe| {
        pfe.* = paging.PFE_DEFAULTS[0];
        pfe.setGlobal(0, true);
        pfe.setEntry(0, buddy.allocPage4k());
    }

    return @ptrFromInt(area.start.val);
}

pub fn vmalloc(comptime T : type) *T {
    std.debug.assert(@alignOf(T) <= types.SIZE_4KB);

    return @ptrCast(@alignCast(vmallocBytes(@sizeOf(T))));
}

pub fn vfreeBytes(addr : *anyopaque) void {
    const vmSpace = &kernel.kernelProcess.addrSpace;
    var mas = lib.linux.MapleTree.MaState.create(&vmSpace.tree, @intFromPtr(addr), @intFromPtr(addr));

    mas.lock();

    const area = cast.toPtr(*vmm.VmArea, mas.find(@intFromPtr(addr)) orelse {
        @panic("Double free of vfree detected!");
    });

    mas.setRange(area.start, area.end - 1);
    mas.erase();
    mas.unlock();

    const pfeState = kernel.PfeState(.UNMAP).create(vmSpace, area.start, area.end, false, .LEVEL_4KB);
    {
        vmSpace.spinlock.lock();
        defer vmSpace.spinlock.unlock();

        while (pfeState.next()) |pfe| {
            const entry = pfe.getEntry(0);
            buddy.freePage4k(entry);
        }
    }

    // Flush TLB
    kernel.SmpRequest.create(kernel.cpuMaskFull(), true, null, .{
        .func = paging.flushPages,
        .args = .{area.start, area.end},
    });

    pfree(vmm.VmArea, area);
}

pub fn vfree(comptime T : type, addr : *T) void {
    pfreeBytes(addr);
}

pub fn setup() void {
    print("\nmm: Setting up Memory Management\n", .{});

    print("  Phys Addr Bits: {}, Virt Addr Bits: {}\n", .{cpu.FEATURES.PHYS_ADDR_BITS, cpu.FEATURES.VIRT_ADDR_BITS});

    //Set the max size for virt and phys memory addresses
    PHYS_ADDR_SIZE = bin.setBits(cpu.FEATURES.PHYS_ADDR_BITS);
    VIRT_ADDR_SIZE = bin.setBits(cpu.FEATURES.VIRT_ADDR_BITS);

    // The start of kernel memory depending on the number of virtual address bits
    USER_MEMORY_END.val = bin.setBits(cpu.FEATURES.VIRT_ADDR_BITS - 1);
    KERNEL_MEMORY_START.val = ~USER_MEMORY_END.val;

    // PAGE_OFFSET region uses 1/4 of virtual memory
    PAGE_OFFSET_SIZE = bin.setBit(cpu.FEATURES.VIRT_ADDR_BITS - 2);

    // KERNEL_ALLOC region uses 1/8 of virtual memory
    KERNEL_ALLOC_SIZE = bin.setBit(cpu.FEATURES.VIRT_ADDR_BITS - 3);

    PAGE_METADATA_SIZE = (PAGE_OFFSET_SIZE / @sizeOf(paging.PageInfo));

    KERNEL_MEMORY.val = KERNEL_MEMORY_START.val;
    KERNEL_ALLOC.val = PAGE_OFFSET_SIZE + KERNEL_MEMORY.val;
    PAGE_METADATA.val = KERNEL_ALLOC_SIZE + KERNEL_ALLOC.val;
    PER_CPU_DATA.val = PAGE_METADATA.val + bin.alignUp(PAGE_METADATA_SIZE, PER_CPU_DATA_SIZE);

    print("  Kernel Memory Start:   0x{X}\n", .{KERNEL_MEMORY.val});
    print("  Kernel VMalloc Region: 0x{X}\n", .{KERNEL_ALLOC.val});
    print("  Page Metadata Region:  0x{X}\n", .{PAGE_METADATA.val});
    print("  Per CPU Data Region:   0x{X}\n", .{PER_CPU_DATA.val});

    pmm.setup();

    lib.linux.MapleTree.setup();

    lib.linux.XArray.setup();

    vmm.setup();

    kernel.io.irq.setup();

    kernel.pm.time.setup();

    kernel.pm.ipc.rcu.setup();
}