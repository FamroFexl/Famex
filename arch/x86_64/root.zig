pub const cpu = @import("cpu.zig");
pub const reg = @import("registers.zig");
pub const irq = @import("irq.zig");
pub const apic = @import("apic.zig");
pub const ports = @import("ports.zig");

const std = @import("std");
const kernel = @import("kernel");

// Zig can't find ASM symbols automatically, so we have to make them obvious
comptime {
    _ = irq;
    _ =  @import("init.zig");
}

pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_trace;
    _ = ret_addr;
    kernel.log.printDirect("PANIC: ");
    kernel.log.printDirect(msg);
    @trap();
}