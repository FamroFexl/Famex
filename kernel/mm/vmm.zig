const kernel = @import("kernel");
const MapleTree = @import("lib").linux.MapleTree;

const Vaddr = @import("memory.zig").Vaddr;
const paging = @import("paging.zig");
const mem = @import("memory.zig");

const arch = @import("arch");

/// Zeroed/empty page used for reads of uninitialized mmaps
pub var EMPTY_PAGE : arch.paging.Pte = undefined;

pub const VmArea = struct {
    start : Vaddr,      // Start address of the area
    end : Vaddr,        // End address of the area
    flags : Flags,
    areaType : AreaType,
    file : u64,
    fileOffset : usize,

    const AreaType = enum {
        VMALLOC,
        MMIO,
        USER_PROG,
        USER_STACK,
        USER_HEAP,
    };

    const Flags = packed struct {
        read : bool = true,
        write : bool = true,
        exec : bool = true,
        shared : bool = false,
        reserved : bool = false,
    };
};

pub const VmSpace = struct {
    spinlock : kernel.Spinlock = .create(),
    cpuMask : kernel.CpuMask = 0,
    rootPt : *paging.Ptable,
    start : Vaddr,
    end : Vaddr,
    tree : MapleTree,
};

pub fn mapKernelTables(table : *paging.Ptable) void {
    @memcpy(table.pte[256..], kernel.kernelProcess.addrSpace.rootPt.pte[256..]);
}

pub fn setup() void {
    kernel.print("\nmm: Setting up Virtual Memory Management\n", .{});

    kernel.mm.slubAlloc.slubPoolPmalloc(@sizeOf(VmArea));
    kernel.mm.slubAlloc.slubPoolPmalloc(@sizeOf(VmSpace));

    EMPTY_PAGE = paging.PFE_DEFAULTS[0];
    EMPTY_PAGE.setWrite(0, false);
    EMPTY_PAGE.setUser(0, true);
    EMPTY_PAGE.setEntry(0, kernel.zallocPage4k());

    kernel.print("  Initializing kernel vm space\n", .{});
    const vmSpace = &kernel.kernelProcess.addrSpace;
    vmSpace.start = mem.KERNEL_ALLOC;
    vmSpace.end = .asVirt(mem.KERNEL_ALLOC.val +  mem.KERNEL_ALLOC_SIZE);
    vmSpace.spinlock.init();
    vmSpace.cpuMask = kernel.cpuMaskFull();

    kernel.print("  Filling top kernel page table entries\n", .{});
    paging.setupRootPt(vmSpace.rootPt);

    vmSpace.tree.init(.{.allocRange = true});
}