const kernel = @import("kernel");
const bin = kernel.util.bin;
const mm = kernel.mm;
const print = kernel.util.log.print;

const reg = @import("registers.zig");
const cpu = @import("arch_api").cpu;
const apic = @import("apic.zig");

pub extern const irqStubTable : [256]u64;

// Interrupt Descriptor Table exeception/interrupt vectors (local APIC internal)
pub const VecNum = enum(u8) {
    DIVIDE_ERROR        = 0,    // Divide error (fault)
    DEBUG_XCP           = 1,    // Debug exception (fault/trap)
    NON_MASK_IRQ        = 2,    // Non-maskable external interrupt (interrupt)
    BREAKPOINT          = 3,    // Breakpoint (trap)
    OVERFLOW            = 4,    // Overflow (trap)
    BOUND_RANGE         = 5,    // Bound range exceeded (fault)
    BAD_OPCODE          = 6,    // Invalid opcode (fault)
    NO_MATH_CPU         = 7,    // Device not available (no math coprocessor) (fault)
    DOUBLE_FAULT        = 8,    // Double fault (abort) (error code)
    BAD_TSS             = 10,   // Invalid TSS (fault) (error code)
    BAD_SEG             = 11,   // Segment not present (fault) (error code)
    BAD_STACK_SEG       = 12,   // Stack segment (fault) (error code)
    GEN_PROTECT         = 13,   // General protection (fault) (error code)
    PAGE_FAULT          = 14,   // Page (fault) (error code)
    FPU_ERROR           = 16,   // X87 FPU error (fault)
    ALIGN_CHECK         = 17,   // Alignment check (fault) (error code)
    MACHINE_CHECK       = 18,   // Machine check (abort)
    SIMD_FP_XCP         = 19,   // SIMD FP exception (fault)
    VIRT_XCP            = 20,   // Virtualization exception (fault)
    CTRL_PROT_XC        = 21,   // Control protection exception (fault) (error code)

    UINT_START          = 32,   // User-defined interrupts start
    UINT_END            = 252,  // User-defined interrupts end
    IPI                 = 253,  // Inter-Processor Interrupt generic entry
    LOCAL_TIMER         = 254,  // Local timer (LAPIC Timer One-Shot or TSC Deadline) entry
    SIVR                = 255,  // Spurious Interrupt Vector Register entry
};

/// Interrupt handler (called by asm)
///
/// state: used to save and restore registers for a task
/// error: pushed by specific interrupts, otherwise contains garbage (rip)
/// vec_num: what needs to be done depending on interrupt vector type
///
pub export fn interruptVectorHandler(state : *reg.CpuState, err : u64, vec_num : u64) void {
    _ = state;
    _ = err;
    _ = vec_num;
}