const reg = @import("registers.zig");
const kernel = @import("kernel");

pub extern const irq_stub_table : [256]*anyopaque;

/// Interrupt handler (called by asm)
///
/// state: used to save and restore registers for a task
/// error: pushed by specific interrupts, otherwise contains garbage (rip)
/// vec_num: what needs to be done depending on interrupt vector type
///
pub export fn interrupt_vector_handler(state : *reg.CpuState, err : u64, vec_num : u64) callconv(.c) void {
    _ = state;
    _ = err;
    _ = vec_num;
}