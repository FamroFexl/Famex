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
        return .fail(.EINVAL);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    var sigAction = process.sigAction[@intCast(sig)];
    process.spinlock.unlock();

    if (@intFromPtr(oact) != 0) {
        if (mem.copyToUser(oact, &sigAction, @sizeOf(posix.signal.sigaction)) > 0)
            return .fail(.EFAULT);
    }

    if (@intFromPtr(act) != 0) {
        if (mem.copyFromUser(&sigAction, act, @sizeOf(posix.signal.sigaction)) > 0)
            return .fail(.EFAULT);

        process.spinlock.lock();
        defer process.spinlock.unlock();

        process.sigAction[@intCast(sig)] = sigAction;
    }

    return .ok(0);
}

pub fn sigaltstack(state : *cpu.CpuState) SysRet {
    const ss = cast.toPtr(*allowzero posix.signal.stack_t, state.getArgSys(0).*);
    const oss = cast.toPtr(*allowzero posix.signal.stack_t, state.getArgSys(1).*);

    const uThread = kernel.cThread().container().uThread;

    uThread.base.spinlock.lock();
    var sigAltStack = uThread.sigAltStack;
    uThread.base.spinlock.unlock();

    if (@intFromPtr(oss) != 0) {
        if (mem.copyToUser(oss, &sigAltStack, @sizeOf(posix.signal.stack_t)) > 0)
            return .fail(.EFAULT);
    }

    if (@intFromPtr(ss) != 0) {
        if (ss.ss_flags.SS_ONSTACK)
            return .fail(.EINVAL);
        if (ss.ss_size < posix.signal.MINSIGSTKSZ)
            return .fail(.ENOMEM);
        if (uThread.sigAltStack.ss_flags.SS_ONSTACK)
            return .fail(.EPERM);

        // Check for invalid stack. Very important since stack address determines operating mode.
        const lastAddr = @addWithOverflow(@intFromPtr(ss.ss_sp), ss.ss_size);
        if (lastAddr[1] == 1 or lastAddr[0] > mem.USER_MEMORY_END.val + 1)
            return .fail(.EFAULT);

        if (mem.copyFromUser(&sigAltStack, ss, @sizeOf(posix.signal.stack_t)) > 0)
            return .fail(.EFAULT);

        uThread.base.spinlock.lock();
        uThread.sigAltStack = sigAltStack;
        uThread.base.spinlock.unlock();
    }

    return .ok(0);
}

pub fn pthread_sigmask(state : *cpu.CpuState) SysRet {
    const how : posix.signal.SigSet = @enumFromInt(@as(u32, @truncate(state.getArgSys(0).*)));
    const set = cast.toPtr(*allowzero posix.signal.sigset_t, state.getArgSys(1).*);
    const oset = cast.toPtr(*allowzero posix.signal.sigset_t, state.getArgSys(2).*);

    const uThread = kernel.cThread().container().uThread;

    uThread.base.spinlock.lock();
    const sigMask = uThread.sigMask;
    uThread.base.spinlock.unlock();

    if (@intFromPtr(oset) != 0) {
        if (mem.copyToUser(oset, &sigMask, @sizeOf(posix.signal.sigset_t)) > 0)
            return .fail(.EFAULT);
    }

    if (@intFromPtr(set) != 0) {
        var userSet : posix.signal.sigset_t = undefined;
        if (mem.copyFromUser(&userSet, set, @sizeOf(posix.signal.sigset_t)) > 0)
            return .fail(.EFAULT);

        uThread.base.spinlock.lock();
        defer uThread.base.spinlock.unlock();

        uThread.sigMask = switch (how) {
            .SIG_BLOCK => uThread.sigMask | userSet,
            .SIG_SETMASK => userSet,
            .SIG_UNBLOCK => uThread.sigMask & (~userSet),
            _ => return .fail(.EINVAL),
        };
    }

    return .ok(0);
}

pub fn sigqueue(state : *cpu.CpuState) SysRet {
    const pid : posix.types.pid_t = @bitCast(@as(u32, @truncate(state.getArgSys(0).*)));
    const signo : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(1).*)));
    const value = @as(posix.signal.sigval, @bitCast(state.getArgSys(2).*));

    const process = cast.toPtr(*kernel.Process, kernel.pm.process.pids.find(@intCast(pid)) orelse
        return .fail(.ESRCH)
    );

    const curProc = kernel.cThread().owner;

    if (curProc.creds.ruid != process.creds.ruid
        and curProc.creds.ruid != process.creds.suid
        and curProc.creds.euid != process.creds.ruid
        and curProc.creds.euid != process.creds.suid)
        return .fail(.EPERM);

    if (!posix.signal.sigValid(@as(u32, @intCast(signo))))
        return .fail(.EINVAL);

    const siginfo : posix.signal.siginfo_t = .{
        .si_signo = @enumFromInt(signo),
        .si_pid = kernel.cThread().owner.pid,
        .si_uid = kernel.cThread().owner.creds.ruid,
        .si_value = value,
        .si_code = .SI_QUEUE,
    };

    kernel.pm.signal.sigSend(.PROCESS, process, siginfo) catch
        return .fail(.EAGAIN);

    return .ok(0);
}

pub fn sigsuspend(state : *cpu.CpuState) SysRet {
    const sigmask = cast.toPtr(*allowzero posix.signal.sigset_t, state.getArgSys(0).*);

    var outMask : posix.signal.sigset_t = undefined;
    if (mem.copyFromUser(&outMask, sigmask, @sizeOf(posix.signal.sigset_t)) != 0)
        return .fail(.EFAULT);

    const uThread = kernel.cThread().container().uThread;

    const curMask = brk: {
        uThread.base.spinlock.lock();
        defer uThread.base.spinlock.unlock();

        const curMask = uThread.sigMask;
        uThread.sigMask = outMask;
        uThread.base.state = .INTERRUPTABLE;
        break :brk curMask;
    };

    kernel.irqSave();
    uThread.base.sleep();
    kernel.irqRestore();

    {
        uThread.base.spinlock.lock();
        defer uThread.base.spinlock.unlock();

        uThread.sigMask = curMask;
    }

    return .fail(.EINTR);
}

pub fn pause(state : *cpu.CpuState) SysRet {
    _ = state;

    const thread = kernel.cThread();

    {
        thread.spinlock.lock();
        defer thread.spinlock.unlock();

        thread.state = .INTERRUPTABLE;
    }

    kernel.irqSave();
    kernel.cThread().sleep();
    kernel.irqRestore();

    return .fail(.EINTR);
}

// Check for signals in the set
fn sigCheck(sigData : *kernel.pm.signal.SigData, set : posix.signal.sigset_t) ?posix.signal.siginfo_t {
    sigData.spinlock.lock();
    defer sigData.spinlock.unlock();

    const match = sigData.pendingMask & set;
    if (match != 0) {
        const signo = @ctz(match);

        var siginfo : posix.signal.siginfo_t = undefined;
        if (signo < posix.signal.SIGRTMIN) {
            siginfo = sigData.pending[signo];
            kernel.bin.clearFlag(signo, &sigData.pendingMask);
        }
        else {
            const queue = &sigData.pendingRT[posix.signal.SIGRTMIN - signo];
            const sigLink : *kernel.pm.signal.SigRTLink = @fieldParentPtr("link", queue.pop().?);
            if (queue.empty())
                kernel.bin.clearFlag(signo, &sigData.pendingMask);

            siginfo = sigLink.signal;
            kernel.pfree(kernel.pm.signal.SigRTLink, sigLink);
        }

        return siginfo;
    }

    return null;
}

pub fn sigtimedwait(state : *cpu.CpuState) SysRet {
    const set = cast.toPtr(*allowzero posix.signal.sigset_t, state.getArgSys(0).*);
    const info = cast.toPtr(*allowzero posix.signal.siginfo_t, state.getArgSys(1).*);
    const timeout = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(2).*);

    var setOut : posix.signal.sigset_t = undefined;
    if (mem.copyFromUser(&setOut, set, @sizeOf(posix.signal.sigset_t)) != 0)
        return .fail(.EFAULT);

    const uThread = kernel.cThread().container().uThread;

    // Check for valid signals on entry
    if (sigCheck(&uThread.sigData, setOut) orelse sigCheck(&uThread.base.owner.sigData, setOut)) |siginfo| {
        if (@intFromPtr(info) != 0 and mem.copyToUser(info, &siginfo, @sizeOf(posix.signal.siginfo_t)) != 0) {
            return .fail(.EFAULT);
        }

        return .ok(@intCast(@intFromEnum(siginfo.si_signo)));
    }

    var timeoutOut : posix.times.timespec = undefined;
    if (mem.copyFromUser(&timeoutOut, timeout, @sizeOf(posix.times.timespec)) != 0)
        return .fail(.EFAULT);

    if (timeoutOut.tv_nsec >= 1_000_000_000)
        return .fail(.EINVAL);

    const WaitEvent = struct {
        uThread : *kernel.UThread,
        event : kernel.TimerEvent,

        fn wait(event : *kernel.TimerEvent) void {
            const waitEvent : *@This() = @fieldParentPtr("event", event);

            {
                waitEvent.uThread.base.spinlock.lock();
                defer waitEvent.uThread.base.spinlock.unlock();

                waitEvent.uThread.base.state = .RUNNING;
                waitEvent.uThread.base.wakeReason = .TIMER_EXPIRED;
            }

            waitEvent.uThread.base.wake();
        }
    };

    var waitEvent : WaitEvent = .{
        .event = kernel.TimerEvent.create(.MONOTONIC, .zero(), WaitEvent.wait),
        .uThread = uThread,
    };

    {
        uThread.base.spinlock.lock();
        defer uThread.base.spinlock.unlock();
        uThread.base.state = .INTERRUPTABLE;
    }

    // Set timeout
    waitEvent.event.reset(kernel.pm.time.timespecToTime(timeoutOut), false);

    kernel.irqSave();
    uThread.base.sleep();
    kernel.irqRestore();

    {
        uThread.base.spinlock.lock();
        defer uThread.base.spinlock.unlock();

        if (uThread.base.wakeReason == .TIMER_EXPIRED)
            return .fail(.EAGAIN);
    }

    waitEvent.event.remove();

    // Check for valid signals on wake
    if (sigCheck(&uThread.sigData, setOut) orelse sigCheck(&uThread.base.owner.sigData, setOut)) |siginfo| {
        if (@intFromPtr(info) != 0 and mem.copyToUser(info, &siginfo, @sizeOf(posix.signal.siginfo_t)) != 0) {
            return .fail(.EFAULT);
        }

        return .ok(@intCast(@intFromEnum(siginfo.si_signo)));
    }

    return .fail(.EINTR);
}

// pub fn kill(state : *cpu.CpuState) SysRet {
//     const pid = kernel.bin.convert(posix.types.pid_t, state.getArgSys(0).*);
//     const sig = kernel.bin.convert(i32, state.getArgSys(1).*);
//
//     if (!posix.signal.sigValid(sig))
//         return .fail(.EINVAL);
//
//     kernel.pm.process.pids.get(@intCast(pid)) orelse
//         return .fail(.ESRCH);
//
//
// }

pub fn pthread_kill(state : *cpu.CpuState) SysRet {
    const pthread = kernel.bin.convert(posix.types.pthread_t, state.getArgSys(0).*);
    const sig = kernel.bin.convert(i32, state.getArgSys(1).*);

    const thread = cast.toPtr(*kernel.Thread, kernel.pm.process.tids.get(pthread) orelse {
        return .fail(.ESRCH);
    });

    if (thread.owner != kernel.cThread().owner)
        return .fail(.ESRCH);

    if (!posix.signal.sigValid(sig))
        return .fail(.EINVAL);

    kernel.pm.signal.sigSend(.THREAD, thread, .{
        .si_signo = sig,
        .si_pid = kernel.cThread().owner.pid,
    });

    return .ok(0);
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