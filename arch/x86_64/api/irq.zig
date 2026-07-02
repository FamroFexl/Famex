const kernel = @import("kernel");

const arch = @import("arch");
const cpu = arch.cpu;
const apic = arch.apic;
const irq = arch.irq;

pub fn getIrqType(irqNum : u64) kernel.io.irq.IrqType {
    return switch (irqNum) {
        irq.VecNum.IPI => .IPI,
        irq.VecNum.LOCAL_TIMER => .LOCAL_TIMER,
        irq.VecNum.SIVR => .SPURIOUS,
        0...31 => .EXCEPTION,
        else => .DEVICE,
    };
}

pub fn notifyCpu(cpuId : anytype) void {
    var icr : apic.IcrReg = .{
        .vector = irq.VecNum.IPI,
        .triggerMode = .EDGE,
        .destMode = .LOGICAL,
        .deliveryMode = .FIXED,
        .destShorthand = .NONE,
    };

    apic.setIcrDest(&icr, kernel.Limine.smp_request.response.x86.cpus.x86[cpu.getCpuId()].lapic_id);

    apic.set(.icr, icr);
}