const kernel = @import("kernel");

const irq = @import("irq.zig");

pub fn handler(data : *const irq.IrqData, state : *kernel.CpuState) void {
    _ = data;
    _ = state;
}