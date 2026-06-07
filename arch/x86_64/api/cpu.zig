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
pub const FpuState = anyopaque;

/// Save general registers from the CPU
pub fn save_state(state : *CpuState) void {
    reg.save_regs(state);
}

/// Load general registers into the CPU
pub fn load_state(state : *CpuState) void {
    reg.load_regs(state);
}

/// Save FPU registers from the CPU
pub fn save_fpu(state : *FpuState) void {
    reg.save_regs_fpu(state);
}

/// Load FPU registers into the CPU
pub fn load_fpu(state : *FpuState) void {
    reg.load_regs_fpu(state);
}

/// Allocate an appropriately-sized FPU register state
//pub fn alloc_fpu() *FpuState {}

/// Free a FPU state
//pub fn free_fpu(state : *FpuState) void {}

/// Get a state's program counter
pub fn get_pc(state : *CpuState) u64 {
    return state.rip;
}

/// Set a state's program counter
pub fn set_pc(state : *CpuState, pc : u64) void {
    state.rip = pc;
}

/// Get a state's stack
pub fn get_stack(state : *CpuState) u64 {
    return state.rsp;
}

/// Set a state's stack
pub fn set_stack(state : *CpuState, stack : u64) void {
    state.rsp = stack;
}

/// Get a state's flags
pub fn get_flags(state : *CpuState) u64 {
    return state.rflags;
}

/// Set a state's flags
pub fn set_flags(state : *CpuState, flags : u64) void {
    state.rflags = flags;
}

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
pub fn spin_wait_loop() void {
    asm volatile ("pause");
}

/// Entry position for the idle task
pub fn idle_entry() noreturn {
    while (true) {
        asm volatile ("sti\nhlt");
    }
}

/// Enable IRQs
pub fn irq_enable() void {
    asm volatile ("sti");
}

/// Disable IRQs
pub fn irq_disable() void {
    asm volatile ("cli");
}

/// Get if IRQs are enabled
pub fn irq_enabled() bool {
    return reg.get_rflags().irq_enable;
}

/// Get a register pointer from an argument number
pub fn get_arg(state : *CpuState, arg : u8) *u64 {
    return switch (arg) {
        0 => &state.rdi,
        1 => &state.rsi,
        2 => &state.rdx,
        3 => &state.rcx,
        4 => &state.r8,
        5 => &state.r9,
        else => unreachable,
    };
}

/// Get the return register pointer
pub fn get_ret(state : *CpuState) *u64 {
    return &state.rax;
}

/// Get a register pointer from an argument number (for syscall register format)
pub fn get_arg_syscall(state : *CpuState, arg : u8) *u64 {
    return switch (arg) {
        2 => &state.r10,
        else => get_arg(state, arg),
    };
}
