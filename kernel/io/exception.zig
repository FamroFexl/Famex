const kernel = @import("kernel");

const irq = @import("irq.zig");

pub fn handler(data : *irq.IrqData, state : *kernel.CpuState) void {

}