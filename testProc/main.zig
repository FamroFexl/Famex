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
var siggot = false;
fn sighandler(signo : i32, siginfo : *posix.signal.siginfo_t, ucontext : *posix.signal.ucontext_t) callconv(.c) void {
    siggot = true;
    _ = signo;
    _ = siginfo;
    _ = ucontext;
}

export fn main() void {
    sys.print("hello!\n", .{});

    var act : posix.signal.sigaction = .{
        .sa_flags = .{.SA_ONSTACK = true},
        .sa_handler = @enumFromInt(@intFromPtr(&sighandler)),
        .sa_mask = 0,
    };
    _ = sys.sigaction(@intFromEnum(posix.signal.Signal.SIGALRM), &act, @ptrFromInt(0));

    const addr = sys.mmap(@ptrFromInt(8), 0x4000, .{
        .READ = true, .WRITE = true,
    }, .{ .ANONYMOUS = true }, -1, 0);

    const altStack : posix.signal.stack_t = .{
        .ss_flags = .{},
        .ss_size = 0x2000,
        .ss_sp = addr,
    };
    _ = sys.sigaltstack(&altStack, @ptrFromInt(0));

    sys.print("time {}\n", .{sys.time(@ptrFromInt(0))});

    _ = sys.alarm(4);
    //_ = sys.alarm(0);

    sys.print("hello2\n", .{});

    while (!siggot) {}

    sys.print("time {}\n", .{sys.time(@ptrFromInt(0))});

    sys.print("after signal!\n", .{});
}