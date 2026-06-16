pub const cpu = @import("registers.zig");
pub const reg = @import("registers.zig");
pub const irq = @import("irq.zig");

// Zig can't find ASM symbols automatically, so we have to make them obvious
comptime {
    _ = irq;
    _ =  @import("init.zig");
    _ = @import("kernel");
}