const std = @import("std");

pub export fn _start() noreturn {
    main();
    while (true) {}
}

pub inline fn syscall(number: u64, args: [6]u64) u64 {
    return asm volatile (
        \\ syscall
    : [ret] "={rax}" (-> u64),
        : [num] "{rax}" (number),
          [a0] "{rdi}" (args[0]),
          [a1] "{rsi}" (args[1]),
          [a2] "{rdx}" (args[2]),
          [a3] "{r10}" (args[3]),
          [a4] "{r8}" (args[4]),
          [a5] "{r9}" (args[5]),
        : .{.rcx = true, .r11 = true, .rbx = true, .memory = true }
    );
}

pub fn print(comptime str : []const u8, args: anytype) void {
    var buf : [100]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, str, args) catch {
        const err = "bufPrint overflow\n";
        _ = syscall(1, .{@intFromPtr(err[0..].ptr), err.len, 0, 0, 0, 0});
        return;
    };
    _ = syscall(1,.{@intFromPtr(out.ptr), out.len, 0, 0, 0, 0});
}

pub fn yield() void {
    _ = syscall(2, .{0, 0, 0, 0, 0, 0});
}

pub const timespec = extern struct {
    tv_sec : u64,  // Whole seconds.
    tv_nsec : i64,          // Nanoseconds [0, 999999999].
};

export fn main() void {
    print("hello!\n", .{});
    const out = syscall(8, .{0, 80, 0b011, 1,  @bitCast(@as(i64, @intCast(-1))), 0});
    const mem : [*]volatile u8 = @ptrFromInt(out);

    _ = mem[0];

    print("between\n", .{});
    mem[0] = 8;
    print("hello9", .{});
}