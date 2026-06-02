pub const cpu = @import("cpu.zig");

export fn main() void {
    @import("init.zig").init();
}