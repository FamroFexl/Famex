/// Save state for general registers
pub const CpuState= @import("arch").reg.CpuState;
const reg = @import("arch").reg;
const cpu = @import("arch").cpu;

const proc = @import("kernel").pm.process;

const CpuFeatures = struct {
    PHYS_ADDR_BITS : u8,        // Physical memory address bits
    VIRT_ADDR_BITS : u8,        // Virtual memory address bits
    CACHELINE_SIZE : u16,
    MAX_PAGE_SIZE : u3,         // Max page size in levels (starting from 0)
    PAGE_TABLE_LEVELS : u8,     // Number of page table levels (starting from 1)
    EXECUTE_BIT : bool,
    READ_BIT : bool,
    NUM_CPU_CORES : u64,
};

pub var FEATURES : CpuFeatures = undefined;

/// Save state for FPU registers
pub const FpuState = struct {
    regs : *anyopaque,

    /// Allocate an appropriately-sized FPU register state
    pub fn alloc() *@This() {
        return .{.regs = cpu.FP_SAVE_POOL.alloc()};
    }

    /// Free a FPU state
    pub fn free(state : *@This()) void {
        cpu.FP_SAVE_POOL.free(state.regs);
    }

    extern fn fxSave(state : *anyopaque) callconv(.c) void;
    extern fn xSave(state : *anyopaque) callconv(.c) void;
    /// Save FPU registers from the CPU
    pub fn save(state : *@This()) void {
        if (cpu.XSAVE_ON) {
            xSave(state.regs);
        }
        else {
            fxSave(state.regs);
        }
    }

    extern fn fxLoad(state : *anyopaque) callconv(.c) void;
    extern fn xLoad(state : *anyopaque) callconv(.c) void;
    /// Load FPU registers into the CPU
    pub fn load(state : *@This()) void {
        if (cpu.XSAVE_ON) {
            xLoad(state.regs);
        }
        else {
            fxLoad(state.regs);
        }
    }
};

/// Get the current CPU flags
pub fn getCurFlags() u64 {
    return reg.Rflags.get();
}

/// Set the current CPU flags
pub fn setCurFlags(flags : u64) void {
    reg.Rflags.set(flags);
}

/// Get the per-CPU pointer
pub fn getPerCpu() *anyopaque {
    return @ptrFromInt(reg.GsBase.get());
}

/// Set the per-CPU pointer
pub fn setPerCpu(per_cpu : *anyopaque) void {
    reg.GsBase.set(@intFromPtr(per_cpu));
}

/// Spin loop optimization
pub extern fn spinWaitLoop() callconv(.c) void;

/// Entry position for the idle task
pub extern fn idleEntry() callconv(.c) noreturn;

/// Enable IRQs
pub extern fn irqEnable() callconv(.c) void;

/// Disable IRQs
pub extern fn irqDisable() callconv(.c) void;

/// Get if IRQs are enabled
pub fn irqEnabled() bool {
    return reg.Rflags.get().irq_enable;
}

pub fn getCpuId() u8 {
    return cpu.cpuId.getLocal().*;
}
