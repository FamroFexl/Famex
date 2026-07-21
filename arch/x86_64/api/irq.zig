const kernel = @import("kernel");

const arch = @import("arch");
const cpu = arch.cpu;
const apic = arch.apic;
const irq = arch.irq;

pub fn getIrqType(irqNum : u64) kernel.io.irq.IrqType {
    return switch (irqNum) {
        @intFromEnum(irq.VecNum.IPI) => .IPI,
        @intFromEnum(irq.VecNum.LOCAL_TIMER) => .LOCAL_TIMER,
        @intFromEnum(irq.VecNum.SIVR) => .SPURIOUS,
        0...31 => .EXCEPTION,
        else => .DEVICE,
    };
}

pub fn getExceptionType(irqNum : u64) kernel.io.exception.ExceptionType {
    const vecNum = @as(irq.VecNum, @enumFromInt(irqNum));
    return switch (vecNum) {
        .DIVIDE_ERROR, .OVERFLOW, .NO_MATH_CPU, .FPU_ERROR, .SIMD_FP_XCP => .MATH_ERROR,
        .BOUND_RANGE, .BAD_TSS, .BAD_SEG, .BAD_STACK_SEG => .BAD_ADDR,
        .ALIGN_CHECK => .ALIGN_FAULT,
        .DEBUG_XCP, .BREAKPOINT => .TRAP,
        .GEN_PROTECT, .NON_MASK_IRQ, .VIRT_XCP, .DOUBLE_FAULT, .MACHINE_CHECK => .GENERAL_FAULT,
        else => @panic("Unhandled exception!"),
    };
}

pub fn notifyCpu(cpuId : anytype) void {
    const icrBase : apic.IcrReg = .{
        .vector = @intFromEnum(irq.VecNum.IPI),
        .triggerMode = .EDGE,
        .destMode = .PHYSICAL,
        .deliveryMode = .FIXED,
        .destShorthand = .NONE,
    };

    var icrOut = icrBase;

    apic.setIcrDest(&icrOut, kernel.Limine.smp_request.response.x86.cpus.x86[cpuId].lapic_id);

    apic.set(.icr, icrOut);
}