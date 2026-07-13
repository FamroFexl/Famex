const kernel = @import("kernel");
const MapleTree = @import("lib").linux.MapleTree;

const Vaddr = @import("memory.zig").Vaddr;
const paging = @import("paging.zig");
const mem = @import("memory.zig");

pub const VmArea = struct {
    start : Vaddr,      // Start address of the area
    end : Vaddr,        // End address of the area
    flags : Flags,
    areaType : AreaType,
    // file
    // file_offset

    const AreaType = enum {
        VMALLOC,
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
    @memcpy(table.pte[256..], kernel.kernelProcess.addr_space.rootPt.pte[256..]);
}

pub fn setup() void {
    kernel.print("\nmm: Setting up Virtual Memory Management\n", .{});

    kernel.mm.slubAlloc.slubPoolPmalloc(@sizeOf(VmArea));
    kernel.mm.slubAlloc.slubPoolPmalloc(@sizeOf(VmSpace));

    kernel.print("  Initializing kernel vm space\n", .{});
    const vmSpace = &kernel.kernelProcess.addr_space;
    vmSpace.start = mem.KERNEL_ALLOC;
    vmSpace.end = .asVirt(mem.KERNEL_ALLOC.val +  mem.KERNEL_ALLOC_SIZE);
    vmSpace.spinlock.init();
    vmSpace.cpuMask = kernel.cpuMaskFull();

    kernel.print("  Filling top kernel page table entries\n", .{});
    paging.setupRootPt(vmSpace.rootPt);

    vmSpace.tree.init(.{.allocRange = true});
}