const kernel = @import("kernel");

const irqIn = kernel.PerCpuStat(bool);

pub fn inIrq() bool {
    return irqIn.getLocal().*;
}