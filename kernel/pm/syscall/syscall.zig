const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;

const lib = @import("lib");
const errno = lib.posix.errno;

const cpu = @import("arch").cpu;

const sched = @import("sched.zig");
const time = @import("time.zig");


// Handle a specified syscall
pub export fn syscallHandler(state : *cpu.CpuState) void {
    const uThread : *kernel.UThread = @fieldParentPtr("base", kernel.cThread());

    uThread.flags.inSyscall = true;
    defer uThread.flags.inSyscall = false;

    kernel.pm.ipc.rcu.exitEqs();

    kernel.pm.process.addUtime();

    kernel.irqEnable();

    const sysNum = state.getRetSys().*;

    state.getRetSys().* = @bitCast(syscall(sysNum, state));

    kernel.irqDisable();

    // Check for signals with the current thread

    kernel.pm.process.addKtime();

    kernel.pm.ipc.rcu.enterEqs();
}

fn print(state : *cpu.CpuState) i64 {
    const ptr = cast.toPtr([*]const u8, state.getArgSys(0).*);
    const len = state.getArgSys(1).*;
    var buf : [1000]u8 = undefined;
    if (cpu.copyFromUser(&buf, cast.toPtr(*anyopaque, ptr), len) > 0) {
        kernel.print("Error, couldn't copy!\n", .{});
    }
    else {
        kernel.log.printChars(&buf, len);
    }

    return 0;
}

fn syscall(sysNum : u64, state : *cpu.CpuState) i64 {
    return switch (sysNum) {
        1 => print(state),
        2 => sched.sched_yield(state),

        3 => time.time(state),
        // 5 => time.clock_getcpuclockid(state),
        // 6 => time.clock_getres(state),
        // 7 => time.clock_gettime(state),
        // 8 => time.clock_settime(state),
        else => -errno.ENOSYS,
    };
}
