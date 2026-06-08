pub const cpu = @import("cpu.zig");
pub const reg = @import("registers.zig");
pub const irq = @import("irq.zig");

// Zig can't find ASM symbols automatically, so we have to make them obvious
comptime {
    _ = irq.interrupt_vector_handler;
    _ = @import("kernel").pm.process.in_kmode;
    _ =  @import("init.zig").init;
}