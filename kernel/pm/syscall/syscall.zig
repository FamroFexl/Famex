const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const mem = kernel.mm.memory;

const posix = @import("lib").posix;
const errno = posix.errno;

const cpu = @import("arch").cpu;

const sched = @import("sched.zig");
const time = @import("time.zig");
const memory = @import("memory.zig");
const signal = @import("signal.zig");
const creds = @import("creds.zig");
const file = @import("file.zig");

pub var VDSO_PAGE : kernel.Paddr = undefined;
pub var VDSO : *Vdso = undefined;

pub const Vdso = struct {
    monoTime : kernel.Time, // Monotonic time (nanoseconds)
    unixOfst : i64,         // Unix offset (nanoseconds)
    sigReturn : [cpu.getSigRetSize()]u8,    // Sigreturn code

    comptime {
        std.debug.assert(@alignOf(Vdso) == 8);
    }
};

pub const ProcTimer = struct {
    inUse : bool = false,   // Timer has been allocated
    armed : bool = false,   // Timer is currently active

    signo : posix.signal.Signal = undefined,
    signot : posix.signal.SigevNot = undefined,
    sigval : posix.signal.sigval = undefined,

    reset : ?kernel.Time = null, // Interval to reset to
    overrun : u64 = 0,           // Number of times the timer has overrun

    timerType : union(enum) {
        normalTimer : kernel.TimerEvent,
        cpuTimer : struct {
            clockId : posix.types.clockid_t,
            expiration : kernel.Time,
        }
    } = undefined,

    originProc : *kernel.Process = undefined,
};

pub const SysRet = struct {
    ret : u64,

    pub const ERR_BASE = std.math.maxInt(u64);

    pub fn ok(out : u64) @This() {
        return .{.ret = out};
    }

    pub fn fail(err : posix.errno.Errno) @This() {
        return .{.ret = (ERR_BASE - cast.u64(@intFromEnum(err))) + 1};
    }

    pub fn isFail(this : @This()) bool {
        return this.ret >= ERR_BASE - 0x1000;
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

    kernel.io.irq.irqSaveDepth.getLocal().*.* = 0;
    kernel.irqEnable();

    syscall(state);

    kernel.irqDisable();
    kernel.io.irq.irqSaveDepth.getLocal().*.* = 1;

    kernel.pm.signal.sigHandle(state);

    kernel.pm.process.addKtime();

    kernel.pm.ipc.rcu.enterEqs();

    kernel.io.irq.irqSaveDepth.getLocal().*.* = 0;
}

fn print(state : *cpu.CpuState) SysRet {
    const ptr = cast.toPtr([*]allowzero const u8, state.getArgSys(0).*);
    const len = state.getArgSys(1).*;
    var buf : [1000]u8 = undefined;
    if (mem.copyFromUser(&buf, cast.toPtr(*allowzero anyopaque, ptr), len) > 0) {
        kernel.print("Error, couldn't copy!\n", .{});
    }
    else {
        kernel.log.printChars(&buf, len);
    }

    return .ok(0);
}

fn syscall(state : *cpu.CpuState) void {
    const num : posix.sysnum.SysNum = @enumFromInt(state.getRetSys().*);
    state.getRetSys().* = (switch (num) {
        .PRINT => print(state),
        .SCHED_YIELD => sched.sched_yield(state),
        .TIME => time.time(state),
        .CLOCK_GETCPUCLOCKID => time.clock_getcpuclockid(state),
        .CLOCK_GETRES => time.clock_getres(state),
        .CLOCK_GETTIME => time.clock_gettime(state),
        .CLOCK_SETTIME => time.clock_settime(state),
        .MMAP => memory.mmap(state),
        .PTHREAD_SIGMASK => signal.pthread_sigmask(state),
        .SIGALTSTACK => signal.sigaltstack(state),
        .SIGACTION => signal.sigaction(state),
        .SIGQUEUE => signal.sigqueue(state),
        ._SIGRETURN => kernel.pm.signal.sigreturn(state),
        .CLOCK_NANOSLEEP => time.clock_nanosleep(state),
        .ALARM => signal.alarm(state),
        .SIGSUSPEND => signal.sigsuspend(state),
        .PAUSE => signal.pause(state),
        .SIGTIMEDWAIT => signal.sigtimedwait(state),
        .PTHREAD_KILL => signal.pthread_kill(state),
        else => SysRet.fail(.ENOSYS),
    }).ret;
}

pub fn setup() void {
    VDSO_PAGE = kernel.zallocPage4k();
    const vdso = cast.toPtr(*Vdso, VDSO_PAGE.toVirt().ptr());
    cpu.setSigRet(&vdso.sigReturn);

    VDSO = @ptrFromInt(kernel.bin.alignDown(mem.USER_MEMORY_END.val, kernel.types.SIZE_4KB));
}
