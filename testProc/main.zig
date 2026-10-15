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


// fn (i32) void
// fn (i32, *siginfo_t, *ucontext)
fn sighandler(signo : i32, siginfo : *posix.signal.siginfo_t, ucontext : *posix.signal.ucontext_t) callconv(.c) void {
    _ = signo;
    _ = siginfo;
    _ = ucontext;
}

export fn main() void {
    sys.print("hello!\n", .{});

    sys.print("time {}\n", .{sys.time(@ptrFromInt(0))});

    sys.print("after signal!\n", .{});
}