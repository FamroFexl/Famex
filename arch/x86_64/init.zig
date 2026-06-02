const print = @import("kernel").util.print.print;
const cpuid = @import("lib").cpuid_db;
const cpu = @import("cpu.zig");
const mm = @import("kernel").mm;

pub fn init() void {
    const out = cpu.cpuid(cpuid.leaf_0x80000008_0, 0x80000008, 0);

    mm.memory.PHYS_ADDR_BITS = @intCast(out.eax.phys_addr_bits);
    mm.memory.VIRT_ADDR_BITS = @intCast(out.eax.virt_addr_bits);
    mm.paging.PT_LEVEL = 4;

    mm.memory.setup_mem_mgmt();
}