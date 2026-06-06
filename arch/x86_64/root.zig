pub const cpu = @import("cpu.zig");
pub const reg = @import("registers.zig");

export fn main() void {
    @import("init.zig").init();
}