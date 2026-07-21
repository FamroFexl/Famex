const kernel = @import("kernel");
const bin = kernel.util.bin;
const mm = kernel.mm;
const print = kernel.util.log.print;

const reg = @import("registers.zig");
const cpu = @import("arch_api").cpu;
const apic = @import("apic.zig");

pub extern const irqStubTable : [256]u64;

pub extern fn syscallEntry() callconv(.c) void;

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

const PfaultError = packed struct(u64) {
    present     : bool,    // (0) Not present caused fault (1) Protection violation caused fault
    write       : bool,    // (0) Read caused fault (1) Write caused fault
    user_mode   : bool,    // (0) Kernel mode fault (1) User mode fault
    rsvd        : bool,    // Fault caused by reserved bit being set
    instr_ftch  : bool,    // Fault caused by instruction fetch access
    prot_key    : bool,    // Fault caused by protection key violation
    shdw_stack  : bool,    // Fault caused by Shadow-stack access
    hlat_paging : bool,    // (0) Normal paging fault (1) HLAT VM paging fault
    sgx         : bool,    // Fault caused by SGX access control violation
    __pad1      : u55,
};

/// Interrupt handler (called by asm)
///
/// state: used to save and restore registers for a task
/// error: pushed by specific interrupts, otherwise contains garbage (rip)
/// vec_num: what needs to be done depending on interrupt vector type
///
pub export fn interruptVectorHandler(state : *reg.CpuState, err : u64, vec_num : u64) void {
    if (vec_num == 14) {
        kernel.print("Pfault {} ", .{@as(PfaultError, @bitCast(err))});
        kernel.print("0x{x}\n", .{reg.Cr2.get()});
    }
    else {
        kernel.print("VecNum {}", .{vec_num});
        if (err != 0) {
            kernel.print(" {b}\n", .{err});
        }
        else {
            kernel.print("\n", .{});
        }
    }

    if (vec_num == 6 or vec_num == 14) {
        while (true) {}
    }

    var data : ?kernel.io.exception.ExceptionData = null;
    if (vec_num == @intFromEnum(VecNum.PAGE_FAULT)) {
        const pfault : PfaultError = @bitCast(err);
        data.?.pfault = .{
            .addr = .asVirt(reg.Cr2.get()),
            .present = pfault.present,
            .access = if (pfault.instr_ftch) .EXECUTE else if (pfault.write) .WRITE else .READ,
        };
    }

    const irqData : kernel.io.irq.IrqData = .{
        .irqNum = vec_num,
        .data = &data,
    };

    kernel.io.irq.handler(&irqData, state);

    if (vec_num >= @intFromEnum(VecNum.UINT_START))
        apic.set(.eoi, 0);
}