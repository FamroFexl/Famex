/// Save state for general registers
pub const CpuState= @import("arch").reg.CpuState;
const reg = @import("arch").reg;

const CpuFeatures = struct {
    PHYS_ADDR_BITS : u8,        // Physical memory address bits
    VIRT_ADDR_BITS : u8,        // Virtual memory address bits
    MAX_PAGE_SIZE : u3,         // Max page size in levels (starting from 0)
    PAGE_TABLE_LEVELS : u8,     // Number of page table levels
    EXECUTE_BIT : bool,
    READ_BIT : bool,
    NUM_CPU_CORES : u64,
    CACHELINE_SIZE : u16,
};

pub var FEATURES : CpuFeatures = undefined;

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
pub fn getCurFlags() u64 {
    return reg.get_rflags();
}

/// Set the current CPU flags
pub fn setCurFlags(flags : u64) void {
    reg.set_rflags(flags);
}

/// Get the per-CPU pointer
pub fn getPerCpu() *anyopaque {
    return @ptrFromInt(reg.Msr.get(.GS_BASE));
}

/// Set the per-CPU pointer
pub fn setPerCpu(per_cpu : *anyopaque) void {
    reg.Msr.set(.GS_BASE, @intFromPtr(per_cpu));
}

/// Spin loop optimization
pub extern fn spinWaitLoop() callconv(.c) void;

/// Entry position for the idle task
pub extern fn idleEntry() callconv(.c) noreturn;

/// Enable IRQs
pub extern fn irqEnable() callconv(.c) void;

/// Disable IRQs
pub extern fn irqDisabled() callconv(.c) void;

/// Get if IRQs are enabled
pub fn irqEnabled() bool {
    return reg.Rflags.get().irq_enable;
}
