const std = @import("std");

const sys = @import("sys.zig");
const posix = @import("posix");

export fn xprint(val : u64) callconv(.c) void {
    sys.print("xprint 0x{x}\n", .{val});
}

pub export fn _start() noreturn {
    main();
    while (true) {}
}

var siggot = false;
fn sighandler(signo : i32) callconv(.c) void {
    siggot = true;
    sys.print("sighandl {}\n", .{signo});
}

export fn main() void {
    sys.print("hello!\n", .{});

    var act : posix.signal.sigaction = .{
        .sa_flags = .{},
        .sa_handler = @enumFromInt(@intFromPtr(&sighandler)),
        .sa_mask = 0,
    };
    _ = sys.sigaction(@intFromEnum(posix.signal.Signal.SIGALRM), &act, @ptrFromInt(0));

    sys.print("time {}\n", .{sys.time(@ptrFromInt(0))});
    const out = sys.alarm(10);
    //_ = sys.alarm(0);
    sys.print("out {}\n", .{out});

    sys.print("hello2\n", .{});

    while (!siggot) {}

    sys.print("time {}\n", .{sys.time(@ptrFromInt(0))});

    sys.print("after signal!\n", .{});
}