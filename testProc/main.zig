const std = @import("std");

pub export fn _start() noreturn {
    main();
    while (true) {}
}

pub inline fn syscall(number: u64, args: [6]u64) i64 {
    return asm volatile (
        \\ syscall
    : [ret] "={rax}" (-> i64),
        : [num] "{rax}" (number),
          [a0] "{rdi}" (args[0]),
          [a1] "{rsi}" (args[1]),
          [a2] "{rdx}" (args[2]),
          [a3] "{r10}" (args[3]),
          [a4] "{r8}" (args[4]),
          [a5] "{r9}" (args[5]),
        : .{.rcx = true, .r11 = true, .r10 = true, .memory = true }
    );
}

var buf : [1000]u8 = undefined;

pub fn print(comptime str : []const u8, args: anytype) void {
    //var buf : [100]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, str, args) catch {
        const err = "bufPrint err\n";
        _ = syscall(1, .{@intFromPtr(err[0..].ptr), err.len, 0, 0, 0, 0});
        return;
    };
    _ = syscall(1,.{@intFromPtr(out.ptr), out.len, 0, 0, 0, 0});
}

export fn main() void {
    print("hello!\n", .{});
    _ = syscall(2, .{0, 0, 0, 0, 0, 0});
    print("hellove", .{});
}