const kernel = @import("kernel");
const cast = kernel.cast;
const mem = kernel.mm.memory;

const cpu = @import("arch").cpu;

const SysRet = @import("syscall.zig").SysRet;

const posix = @import("lib").posix;

pub fn sigaction(state : *cpu.CpuState) SysRet {
    const sig : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(0).*)));
    const act = cast.toPtr(*allowzero posix.signal.sigaction, state.getArgSys(1).*);
    const oact = cast.toPtr(*allowzero posix.signal.sigaction, state.getArgSys(2).*);

    if (!posix.signal.sigValid(sig) or !posix.signal.sigIgnorable(sig))
        return .fail(posix.errno.EINVAL);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    var sigAction = process.sigAction[@intCast(sig)];
    process.spinlock.unlock();

    if (@intFromPtr(oact) != 0) {
        if (mem.copyToUser(oact, &sigAction, @sizeOf(posix.signal.sigaction)) > 0)
            return .fail(posix.errno.EFAULT);
    }

    if (@intFromPtr(act) != 0) {
        if (mem.copyFromUser(&sigAction, act, @sizeOf(posix.signal.sigaction)) > 0)
            return .fail(posix.errno.EFAULT);

        process.spinlock.lock();
        defer process.spinlock.unlock();

        process.sigAction[@intCast(sig)] = sigAction;
    }

    return .ok(0);
}

pub fn sigaltstack(state : *cpu.CpuState) SysRet {
    const ss = cast.toPtr(*allowzero posix.signal.stack_t, state.getArgSys(0).*);
    const oss = cast.toPtr(*allowzero posix.signal.stack_t, state.getArgSys(1).*);

    const thread = kernel.cThread();

    thread.spinlock.lock();
    var sigAltStack = thread.sigAltStack;
    thread.spinlock.unlock();

    if (@intFromPtr(oss) != 0) {
        if (mem.copyToUser(oss, &sigAltStack, @sizeOf(posix.signal.stack_t)) > 0)
            return .fail(posix.errno.EFAULT);
    }

    if (@intFromPtr(ss) != 0) {
        if (ss.ss_flags.SS_ONSTACK)
            return .fail(posix.errno.EINVAL);
        if (ss.ss_size < posix.signal.MINSIGSTKSZ)
            return .fail(posix.errno.ENOMEM);
        if (thread.sigAltStack.ss_flags.SS_ONSTACK)
            return .fail(posix.errno.EPERM);

        // Check for invalid stack. Very important since stack address determines operating mode.
        const lastAddr = @addWithOverflow(@intFromPtr(ss.ss_sp), ss.ss_size);
        if (lastAddr[1] == 1 or lastAddr[0] > mem.USER_MEMORY_END.val + 1)
            return .fail(posix.errno.EFAULT);

        if (mem.copyFromUser(&sigAltStack, ss, @sizeOf(posix.signal.stack_t)) > 0)
            return .fail(posix.errno.EFAULT);

        thread.spinlock.lock();
        thread.sigAltStack = sigAltStack;
        thread.spinlock.unlock();
    }

    return .ok(0);
}

pub fn pthread_sigmask(state : *cpu.CpuState) SysRet {
    const how : posix.signal.SigSet = @enumFromInt(@as(u32, @truncate(state.getArgSys(0).*)));
    const set = cast.toPtr(*allowzero posix.signal.sigset_t, state.getArgSys(1).*);
    const oset = cast.toPtr(*allowzero posix.signal.sigset_t, state.getArgSys(2).*);

    const thread = kernel.cThread();

    thread.spinlock.lock();
    const sigMask = thread.sigMask;
    thread.spinlock.unlock();

    if (@intFromPtr(oset) != 0) {
        if (mem.copyToUser(oset, &sigMask, @sizeOf(posix.signal.sigset_t)) > 0)
            return .fail(posix.errno.EFAULT);
    }

    if (@intFromPtr(set) != 0) {
        var userSet : posix.signal.sigset_t = undefined;
        if (mem.copyFromUser(&userSet, set, @sizeOf(posix.signal.sigset_t)) > 0)
            return .fail(posix.errno.EFAULT);

        thread.spinlock.lock();
        defer thread.spinlock.unlock();

        thread.sigMask = switch (how) {
            .SIG_BLOCK => thread.sigMask | userSet,
            .SIG_SETMASK => userSet,
            .SIG_UNBLOCK => thread.sigMask & (~userSet),
            _ => return .fail(posix.errno.EINVAL),
        };
    }

    return .ok(0);
}

pub fn sigqueue(state : *cpu.CpuState) SysRet {
    const pid : posix.types.pid_t = @bitCast(@as(u32, @truncate(state.getArgSys(0).*)));
    const signo : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(1).*)));
    const value = @as(posix.signal.sigval, @bitCast(state.getArgSys(2).*));

    const process = cast.toPtr(*kernel.Process, kernel.pm.process.pids.find(@intCast(pid)) orelse
        return .fail(posix.errno.ESRCH)
    );

    const curProc = kernel.cThread().owner;

    if (curProc.creds.ruid != process.creds.ruid
        and curProc.creds.ruid != process.creds.suid
        and curProc.creds.euid != process.creds.ruid
        and curProc.creds.euid != process.creds.suid)
        return .fail(posix.errno.EPERM);

    if (!posix.signal.sigValid(@as(u32, @intCast(signo))))
        return .fail(posix.errno.EINVAL);

    const siginfo : posix.signal.siginfo_t = .{
        .si_signo = @enumFromInt(signo),
        .si_pid = kernel.cThread().owner.pid,
        .si_uid = kernel.cThread().owner.creds.ruid,
        .si_value = value,
    };

    kernel.pm.signal.sigSend(.PROCESS, process, siginfo) catch
        return .fail(posix.errno.EAGAIN);

    return .ok(0);
}

// const sigset_t *sigmask
pub fn sigsuspend(state : *cpu.CpuState) SysRet {
    const sigmask = cast.toPtr(*allowzero posix.signal.sigset_t, state.getArgSys(0).*);

    var outMask : posix.signal.sigset_t = undefined;
    if (mem.copyFromUser(&outMask, sigmask, @sizeOf(posix.signal.sigset_t)) != 0)
        return .fail(posix.errno.EFAULT);

    const thread = kernel.cThread();

    const curMask = brk: {
        thread.spinlock.lock();
        defer thread.spinlock.unlock();

        const curMask = thread.sigMask;
        thread.sigMask = outMask;
        thread.state == .INTERRUPTABLE;
        break :brk curMask;
    };

    thread.sleep();

    {
        thread.spinlock.lock();
        defer thread.spinlock.unlock();

        thread.sigMask = curMask;
    }

    return .fail(posix.errno.EINTR);
}

pub fn alarm(state : *cpu.CpuState) SysRet {
    const seconds = kernel.bin.convert(u32, state.getArgSys(0).*);

    const process = kernel.cThread().owner;
    process.spinlock.lock();

    var sigAlarm  = &process.sigAlarm;

    const remaining = sigAlarm.remaining();

    if (seconds == 0) {
        sigAlarm.remove();
    }
    else {
        sigAlarm.reset(.Sec(seconds), false);
    }

    process.spinlock.unlock();

    if (remaining) |rem|
        return .ok(rem.get(.SEC, false));

    return .ok(0);
}