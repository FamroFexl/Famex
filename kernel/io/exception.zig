const kernel = @import("kernel");
const cast = kernel.cast;

const lib = @import("lib");

const irq = @import("irq.zig");

const arch = @import("arch");

pub const ExceptionType = enum {
    MATH_ERROR,

    PAGE_FAULT,
    ALIGN_FAULT,
    BAD_ADDR,

    TRAP,           // Debug

    BAD_OPCODE,
    GENERAL_FAULT,
};

pub const ExceptionData = union {
    pfault : struct {
        addr : kernel.Vaddr,
        present : bool,
        access : enum { READ, WRITE, EXECUTE }
    }
};

/// Page fault handler lookup table
var pfaultLUT : []struct {fault : u64, handler : u64} = undefined;

pub fn handler(irqNum : u64, data : *ExceptionData, state : *kernel.CpuState) void {
    switch (arch.irq.getExceptionType(irqNum)) {
        .PAGE_FAULT => pageFault(data, state),
        else => @panic("unhandled handler!"),
    }
}

pub fn pageFault(data : *ExceptionData, state : *kernel.CpuState) void {
    _ = data;
    if (state.inKmode()) {
        // Copy from/to user
        for (pfaultLUT) |lut| {
            if (state.getPc() == lut.fault) {
                state.setPc(lut.handler);
                return;
            }
        }
        @panic("Page fault in kernel mode!");
    }
    // Copy on write
    // File paging
    // Zero fill
    // Page swap

    // Invalid mapping
    // No execute
    // Write to read only
    // Access from user to kernel page
}

pub fn setup() void {
    const elf_hdr = cast.toPtr(*lib.elf.ElfHdr, kernel.Limine.executable_file_request.response.*.executable_file.address);
    const shdr = elf_hdr.getShdrByName(".excp_tbl") orelse @panic("Couldn't retrieve the exception table!");

    pfaultLUT.ptr = @ptrFromInt(shdr.addr);
    pfaultLUT.len = shdr.size / 8;
}