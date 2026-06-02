const paging = @import("paging.zig");
const pmm = @import("pmm.zig");
const vmm = @import("vmm.zig");

const print = @import("kernel").util.log.print;
const bin = @import("kernel").util.binary;
const types = @import("kernel").util.types;

pub const paddr = struct {
    val : u64,

    pub fn to_virt(self : paddr) vaddr {
        return self + PAGE_OFFSET.val;
    }

    pub fn to_info(self : paddr) *paging.page_info {
        return @ptrFromInt(PAGE_METADATA + (self / types.SIZE_4KB) * @sizeOf(paging.page_info));
    }
};

pub const vaddr = struct {
    val : u64,

    pub fn to_phys(self : vaddr) paddr {
        return self - PAGE_OFFSET.val;
    }

    pub fn to_info(self : vaddr) *paging.page_info {
        return self.to_phys().to_info();
    }
};

// Physical memory address bits
pub var PHYS_ADDR_BITS : u6 = undefined;
pub var PHYS_ADDR_SIZE : u64 = undefined;

// Virtual memory address bits
pub var VIRT_ADDR_BITS : u6 = undefined;
pub var VIRT_ADDR_SIZE : u64 = undefined;

pub var PAGE_OFFSET_SIZE : usize = undefined;
pub var KERNEL_ALLOC_SIZE : usize = undefined;
pub var PAGE_METADATA_SIZE : usize = undefined;
pub const PER_CPU_DATA_SIZE : usize = types.SIZE_32MB;

pub var PAGE_OFFSET : vaddr = undefined;
pub const USER_MEMORY_START : vaddr = 0x10000;
pub var USER_MEMORY_END : vaddr = undefined;
pub var KERNEL_MEMORY_START : vaddr = undefined;
pub var KERNEL_MEMORY : vaddr = undefined;
pub var KERNEL_ALLOC : vaddr = undefined;
pub var PAGE_METADATA : vaddr = undefined;
pub var PER_CPU_DATA : vaddr = undefined;

pub const KERNEL_IMAGE : vaddr = 0xFFFFFFFF80000000;
pub const MODULE_IMAGES : vaddr = 0xFFFFFFFFA0000000;

pub fn setup_mem_mgmt() void {
    print("\nmm: Setting up Memory Management\n", .{});

    print("  Phys Addr Bits: {}, Virt Addr Bits: {}\n", .{PHYS_ADDR_BITS, VIRT_ADDR_BITS});

    //Set the max size for virt and phys memory addresses
    PHYS_ADDR_SIZE = bin.set_bits(PHYS_ADDR_BITS);
    VIRT_ADDR_SIZE = bin.set_bits(VIRT_ADDR_BITS);

    // The start of kernel memory depending on the number of virtual address bits
    USER_MEMORY_END.val = bin.set_bits(VIRT_ADDR_BITS - 1);
    KERNEL_MEMORY_START.val = ~USER_MEMORY_END.val;

    // PAGE_OFFSET region uses 1/4 of virtual memory
    PAGE_OFFSET_SIZE = bin.set_bits(VIRT_ADDR_BITS - 2);

    // KERNEL_ALLOC region uses 1/8 of virtual memory
    KERNEL_ALLOC_SIZE = bin.set_bits(VIRT_ADDR_BITS - 3);

    PAGE_METADATA_SIZE = (PAGE_OFFSET_SIZE / @sizeOf(paging.page_info));

    KERNEL_MEMORY.val = KERNEL_MEMORY_START.val;
    KERNEL_ALLOC.val = PAGE_OFFSET_SIZE + KERNEL_MEMORY.val;
    PAGE_METADATA.val = KERNEL_ALLOC_SIZE + KERNEL_ALLOC.val;
    PER_CPU_DATA.val = PAGE_METADATA_SIZE + bin.align_up(PAGE_METADATA.val, PER_CPU_DATA_SIZE);

    print("  Kernel Memory Start:   0x{X}\n", .{KERNEL_MEMORY.val});
    print("  Kernel VMalloc Region: 0x{X}\n", .{KERNEL_ALLOC.val});
    print("  Page Metadata Region:  0x{X}\n", .{PAGE_METADATA.val});
    print("  Per CPU Data Region:   0x{X}\n", .{PER_CPU_DATA.val});

    pmm.setup_phys_mem_mgmt();

    vmm.setup_virt_mem_mgmt();

    print("mm: Setting up Read-Copy-Update\n", .{});
}