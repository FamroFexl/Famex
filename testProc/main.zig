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
        : .{ .rcx = true, .r11 = true, .r10 = true, .memory = true }
    );
}

pub fn plunt(str : [:0]const u8) void {
    _ = syscall(1,.{@intFromPtr(str.ptr), 0, 0, 0, 0, 0});
}

export fn main() void {
    plunt("ever");
    plunt("why!");
}