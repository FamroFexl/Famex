const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;

const lib = @import("lib");
const errno = lib.posix.errno;

const cpu = @import("arch").cpu;

const sched = @import("sched.zig");
const time = @import("time.zig");
const memory = @import("memory.zig");

pub const SysRet = struct {
    ret : u64,

    pub const ERR_BASE = std.math.maxInt(u64);

    pub fn ok(out : u64) @This() {
        return .{.ret = out};
    }

    pub fn fail(out : u64) @This() {
        return .{.ret = (ERR_BASE - out) + 1};
    }

    pub fn isFail(this : @This()) bool {
        return this.ret >= ERR_BASE;
    }

    pub fn isOk(this : @This()) bool {
        return !isFail(this);
    }
};

// Handle a specified syscall
pub export fn syscallHandler(state : *cpu.CpuState) void {
    const uThread : *kernel.UThread = @fieldParentPtr("base", kernel.cThread());

    uThread.flags.inSyscall = true;
    defer uThread.flags.inSyscall = false;

    kernel.pm.ipc.rcu.exitEqs();

    kernel.pm.process.addUtime();

    kernel.irqEnable();

    syscall(state);

    kernel.irqDisable();

    // Check for signals with the current thread

    kernel.pm.process.addKtime();

    kernel.pm.ipc.rcu.enterEqs();
}

fn print(state : *cpu.CpuState) SysRet {
    const ptr = cast.toPtr([*]const u8, state.getArgSys(0).*);
    const len = state.getArgSys(1).*;
    var buf : [1000]u8 = undefined;
    if (cpu.copyFromUser(&buf, cast.toPtr(*anyopaque, ptr), len) > 0) {
        kernel.print("Error, couldn't copy!\n", .{});
    }
    else {
        kernel.log.printChars(&buf, len);
    }

    return .ok(0);
}

fn syscall(state : *cpu.CpuState) void {
    state.getRetSys().* = (switch (state.getRetSys().*) {
        1 => print(state),
        2 => sched.sched_yield(state),
        3 => time.time(state),
        4 => time.clock_getcpuclockid(state),
        5 => time.clock_getres(state),
        6 => time.clock_gettime(state),
        7 => time.clock_settime(state),
        8 => memory.mmap(state),
        else => SysRet.fail(lib.posix.errno.ENOSYS),
    }).ret;
}
