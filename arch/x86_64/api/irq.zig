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