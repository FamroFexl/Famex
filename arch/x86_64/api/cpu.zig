/// Save state for general registers
pub const CpuState = @import("arch").reg.CpuState;
const reg = @import("arch").reg;

const CpuFeatures = struct {
    PHYS_ADDR_BITS : u8 = 0,        // Physical memory address bits
    VIRT_ADDR_BITS : u8 = 0,        // Virtual memory address bits
    MAX_PAGE_SIZE : u8 = 0,         // Max page size in levels (starting from 0)
    PAGE_TABLE_LEVELS : u8 = 0,     // Number of page table levels
    EXECUTE_BIT : bool = false,
    READ_BIT : bool = false,
    NUM_CPU_CORES : u64 = 0,
};

pub var FEATURES : CpuFeatures = CpuFeatures {};

/// Save state for FPU registers
pub const FpuState = struct {
    regs : anyopaque,

    // /// Allocate an appropriately-sized FPU register state
    //pub fn alloc() *@This() {}

    // /// Free a FPU state
    //pub fn free(state : *@This()) void {}

    // /// Save FPU registers from the CPU
    //pub extern fn save(state : *@This()) void;

    // /// Load FPU registers into the CPU
    //pub extern fn load(state : *@This()) void;
};

/// Get the current CPU flags
pub fn get_cur_flags() u64 {
    return reg.get_rflags();
}

/// Set the current CPU flags
pub fn set_cur_flags(flags : u64) void {
    reg.set_rflags(flags);
}

/// Get the per-CPU pointer
pub fn get_per_cpu() *anyopaque {
    reg.get_msr(reg.Msrs.GS_BASE);
}

/// Set the per-CPU pointer
pub fn set_per_cpu(per_cpu : *anyopaque) void {
    reg.set_msr(reg.Msrs.GS_BASE, per_cpu);
}

/// Spin loop optimization
pub extern fn spin_wait_loop() callconv(.c) void;

/// Entry position for the idle task
pub extern fn idle_entry() callconv(.c) noreturn;

/// Enable IRQs
pub extern fn irq_enable() callconv(.c) void;

/// Disable IRQs
pub extern fn irq_disable() callconv(.c) void;

/// Get if IRQs are enabled
pub fn irq_enabled() bool {
    return reg.get_rflags().irq_enable;
}
