const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const mem = kernel.mm.memory;

const cpu = @import("arch").cpu;

const SysRet = @import("syscall.zig").SysRet;

const posix = @import("lib").posix;

pub fn time(state : *cpu.CpuState) SysRet {
    const tloc = cast.toPtr(*allowzero posix.types.time_t, state.getArgSys(0).*);

    const out = kernel.getUnixClock().get(.SEC, false);

    if (@intFromPtr(tloc) != 0 and mem.copyToUser(tloc, cast.toPtr(*anyopaque, &out), @sizeOf(posix.types.time_t)) != 0) {
        return .fail(.EFAULT);
    }

    return .ok(out);
}

const ThreadWake = struct {
    thread : *kernel.Thread,
    event : kernel.TimerEvent,
};

pub fn threadWake(event : *kernel.TimerEvent) void {
    const wakeEvent : *ThreadWake = @fieldParentPtr("event", event);

    wakeEvent.thread.spinlock.lock();
    wakeEvent.thread.state = .RUNNING;
    wakeEvent.thread.wakeReason = .TIMER_EXPIRED;
    wakeEvent.thread.spinlock.unlock();

    wakeEvent.thread.wake();
}

pub fn clock_nanosleep(state : *cpu.CpuState) SysRet {
    const clockId : posix.types.clockid_t = @truncate(state.getArgSys(0).*);
    const flags : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(1).*)));
    const rqtp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(2).*);
    const rmtp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(3).*);

    var timeTill : posix.times.timespec = undefined;
    if (mem.copyFromUser(&timeTill, rqtp, @sizeOf(posix.times.timespec)) != 0)
        return .fail(.EFAULT);

    if (timeTill.tv_nsec >= 1000_000_000)
        return .fail(.EINVAL);

    const newTime = kernel.pm.time.timespecToTime(timeTill);

    const clock : posix.times.CLOCK = @enumFromInt(clockId);
    const curTime = switch (clock) {
        .MONOTONIC => kernel.getMonoClock(),
        .REALTIME =>  kernel.getUnixClock(),
        .PROCESS_CPUTIME_ID, .THREAD_CPUTIME_ID => return .fail(.ENOTSUP),
        else => return .fail(.EINVAL),
    };

    const thread = kernel.cThread();

    var wakeEvent : ThreadWake = .{
        .thread = thread,
        .event = kernel.TimerEvent.create(
            switch(clock) { .MONOTONIC => .MONOTONIC, .REALTIME => .UNIX, else => unreachable},
            .zero(),
            threadWake,
        ),
    };

    var abs = false;
    if (kernel.bin.getFlag(posix.times.TIMER_ABSTIME, kernel.bin.convert(u64, flags))) {
        if (newTime.nsec <= curTime.nsec)
            return .ok(0);

        abs = true;
    }

    const expired = wakeEvent.event.reset(newTime, abs);

    if (!expired) {
        thread.spinlock.lock();
        thread.state = .INTERRUPTABLE;
        thread.spinlock.unlock();

        kernel.irqSave();
        thread.sleep();
        kernel.irqRestore();
    }
    else {
        thread.spinlock.lock();
        thread.wakeReason = .TIMER_EXPIRED;
        thread.spinlock.unlock();
    }

    thread.spinlock.lock();
    const wakeReason = thread.wakeReason;
    thread.spinlock.unlock();

    if (wakeReason == .SIGNAL_RECEIVED) {
        // Calculate and copy remaining time
        if (@intFromPtr(rmtp) != 0) {
            const compTime = switch (clock) {
                .MONOTONIC => kernel.getMonoClock(),
                .REALTIME => kernel.getUnixClock(),
                else => unreachable,
            };
            var compSpec = kernel.pm.time.timeToTimespec(compTime);

            if (compTime.nsec > newTime.nsec) {
                if (mem.copyToUser(rmtp, &compSpec, @sizeOf(posix.times.timespec)) != 0)
                    return .fail(.EFAULT);
            }
        }

        return .fail(.EINTR);
    }

    return .ok(0);
}

pub fn clock_getres(state : *cpu.CpuState) SysRet {
    const clockId : posix.types.clockid_t = @truncate(state.getArgSys(0).*);
    const res = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(1).*);

    const out : posix.times.timespec = switch (posix.times.getClockFromId(clockId)) {
        .MONOTONIC, .REALTIME, .PROCESS_CPUTIME_ID, .THREAD_CPUTIME_ID => .{
            .tv_sec = 0,
            .tv_nsec = @intCast(@max(1, (kernel.Time.create(.SEC, 1).nsec + kernel.pm.time.SYSTEM_CLOCK.tps - 1) / kernel.pm.time.SYSTEM_CLOCK.tps)),
        },
        else => return .fail(.EINVAL),
    };

    if (mem.copyToUser(res, cast.toPtr(*anyopaque, &out), @sizeOf(posix.times.timespec)) > 0)
        return .fail(.EFAULT);

    return .ok(0);
}

pub fn clock_getcpuclockid(state : *cpu.CpuState) SysRet {
    const pid : u32 = @truncate(state.getArgSys(0).*);
    const clockId = cast.toPtr(*allowzero posix.types.clockid_t, state.getArgSys(1).*);

    if (pid != kernel.cThread().owner.pid)
        return .fail(.EPERM);

    var out : posix.types.clockid_t = undefined;
    if (pid == 0) {
        out = posix.times.getProcClockFromPid(@intCast(kernel.cThread().owner.pid));
    }
    else {
        _ = kernel.pids.get(pid) orelse return .fail(.ESRCH);
        out = posix.times.getProcClockFromPid(pid);
    }

    if (mem.copyToUser(clockId, &out, @sizeOf(posix.types.clockid_t)) > 0) {
        return .fail(.EFAULT);
    }

    return .ok(0);
}

pub fn clock_gettime(state : *cpu.CpuState) SysRet {
    const clockId : posix.types.clockid_t = @truncate(state.getArgSys(0).*);
    const tp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(1).*);

    const total = switch (posix.times.getClockFromId(clockId)) {
        .MONOTONIC => kernel.getMonoClock(),
        .REALTIME => kernel.getUnixClock(),
        .PROCESS_CPUTIME_ID => brk: {
            const pid = posix.times.getPidFromId(clockId);
            const process = cast.toPtr(*kernel.Process, kernel.pids.get(@intCast(pid)) orelse return .fail(.EINVAL));

            var out : u64 = 0;

            process.spinlock.lock();
            defer process.spinlock.unlock();

            var iter = process.threads.iterator();
            while(iter.next()) |next| {
                const thread : *kernel.Thread = @fieldParentPtr("link", next);

                thread.spinlock.lock();
                defer thread.spinlock.unlock();

                switch (thread.container()) {
                    .uThread => |uThread| {
                        out += uThread.utime.nsec;
                    },
                    else => {},
                }

                out += thread.ktime.nsec;
            }
            break :brk kernel.Time.create(.NSEC, out);
        },
        .THREAD_CPUTIME_ID => brk: {
            const tid = posix.times.getTidFromId(clockId);
            const thread = cast.toPtr(*kernel.Thread, kernel.tids.get(tid) orelse return .fail(.EINVAL));

            thread.spinlock.lock();
            defer thread.spinlock.unlock();

            var out : u64 = 0;
            switch (thread.container()) {
                .uThread => |uThread| {
                    out += uThread.utime.nsec;
                },
                else => {},
            }

            out += thread.ktime.nsec;

            break :brk kernel.Time.create(.NSEC, out);
        },
        .NULL, _ => return .fail(.EINVAL),
    };

    const out = kernel.pm.time.timeToTimespec(total);

    if (mem.copyToUser(tp, cast.toPtr(*anyopaque, &out), @sizeOf(posix.times.timespec)) > 0)
        return .fail(.EFAULT);

    return .ok(0);
}

pub fn clock_settime(state : *cpu.CpuState) SysRet {
    const clockId : posix.types.clockid_t = @truncate(state.getArgSys(0).*);
    const tp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(1).*);

    if (kernel.cThread().owner.creds.euid != 0)
        return .fail(.EPERM);

    var in : posix.times.timespec = undefined;
    if (mem.copyFromUser(&in, tp, @sizeOf(posix.times.timespec)) > 0)
        return .fail(.EFAULT);

    if (in.tv_nsec >= kernel.Time.Sec(100).nsec)
        return .fail(.EINVAL);

    switch (posix.times.getClockFromId(clockId)) {
        .REALTIME => kernel.pm.time.setUnixClock(kernel.pm.time.timespecToTime(in)),
        .PROCESS_CPUTIME_ID, .THREAD_CPUTIME_ID => return .ok(0),    // These can't be set, but can't fail
        else => return .fail(.EINVAL),
    }

    return .ok(0);
}

fn timerCallback(event : *kernel.TimerEvent) void {
    const timer : *kernel.pm.syscall.syscall.ProcTimer = @fieldParentPtr("timerType", event);

    timer.originProc.timersLock.lock();

    if (!timer.armed) {
        timer.originProc.timersLock.unlock();
        return;
    }

    if (timer.reset) |res| {
        _ = event.reset(res, false);
    }
    else {
        timer.armed = false;
    }

    if (timer.signot != .SIGEV_SIGNAL) {
        timer.originProc.timersLock.unlock();

        return;
    }

    const signo = timer.signo;
    const sigval = timer.sigval;
    const origin = timer.originProc;

    const timerNum = (@intFromPtr(timer) - @intFromPtr(&timer.originProc.timers)) / @sizeOf(kernel.pm.syscall.syscall.ProcTimer);

    timer.originProc.timersLock.unlock();

    var overrun = false;

    kernel.pm.signal.sigSend(.PROCESS, origin, .{
        .si_signo = signo,
        .si_value = sigval,
        .si_code = .SI_TIMER,
        .si_status = @intCast(timerNum),
    }) catch |err| switch (err) {
        error.TimerIsQueued => overrun = true,
        else => unreachable,
    };

    timer.originProc.timersLock.lock();

    if (overrun) {
        timer.overrun += 1;
    }
    else {
        timer.overrun = 0;
    }

    timer.originProc.timersLock.unlock();
}

pub fn timer_create(state : *cpu.CpuState) SysRet {
    const clockid : posix.types.clockid_t = kernel.bin.convert(u32, state.getArgSys(0).*);
    const evp = cast.toPtr(*allowzero posix.signal.sigevent, state.getArgSys(1).*);
    const timerid = cast.toPtr(*allowzero posix.types.timer_t, state.getArgSys(2).*);

    const sigevent : posix.signal.sigevent = undefined;
    if (@intFromPtr(evp) != 0 and mem.copyFromUser(&sigevent, evp, @sizeOf(posix.signal.sigevent)) != 0) {
        return .fail(.EFAULT);
    }

    const process = kernel.cThread().owner;

    switch (posix.times.getClockFromId(clockid)) {
        .PROCESS_CPUTIME_ID => {
            if (posix.times.getPidFromId(clockid) != process.pid)
                return .fail(.ENOTSUP);
        },
        .THREAD_CPUTIME_ID => {
            if (posix.times.getTidFromId(clockid) != kernel.cThread().tid)
                return .fail(.ENOTSUP);
        },
        .MONOTONIC => {},
        .REALTIME => {},
        else => return .fail(.EINVAL),
    }

    process.timersLock.lock();

    const timer = brk: {
        for (0..process.timers.len) |i| {
            const timer = &process.timers[i];
            if (!timer.inUse) {
                timer.inUse = true;
                break :brk .{timer, i};
            }
        }

        process.timersLock.unlock();
        return .fail(.EAGAIN);
    };

    if (mem.copyToUser(timerid, &timer[1], @sizeOf(usize)) != 0) {
        // Free the allocated timer
        timer[0].inUse = false;

        process.timersLock.unlock();
        return .fail(.EFAULT);
    }

    if (@intFromPtr(evp) == 0) {
        sigevent = .{
            .sigev_notify = .SIGEV_SIGNAL,
            .sigev_signo = .SIGALRM,
            .sigev_value = .{.sival_int = timer[1]},
        };
    }

    timer[0].signo = sigevent.sigev_signo;
    timer[0].signot = sigevent.sigev_notify;
    timer[0].sigval = sigevent.sigev_value;
    timer[0].armed = false;

    switch (posix.times.getClockFromId(clockid)) {
        .MONOTONIC => {
            process.timersLock.unlock();
            timer[0].timerType.normalTimer = .create(.MONOTONIC, .zero(), timerCallback);
        },
        .REALTIME => {
            process.timersLock.unlock();
            timer[0].timerType.normalTimer = .create(.UNIX, .zero(), timerCallback);
        },
        .THREAD_CPUTIME_ID, .PROCESS_CPUTIME_ID => {
            timer[0].timerType.cpuTimer.clockId = clockid;
        },
        else => {
            process.timersLock.unlock();
            return .fail(.EINVAL);
        },
    }

    if (sigevent.sigev_signo >= posix.signal.SIGRTMIN) {
        process.sigData.spinlock.lock();

        // Reserve a slot if real time
        process.sigData.pendingRTNum += 1;

        process.sigData.spinlock.unlock();
    }

    return .ok(0);
}

pub fn timer_delete(state : *cpu.CpuState) SysRet {
    const timerid : posix.types.timer_t = state.getArgSys(0).*;

    // TimerId out of range
    if (timerid >= posix.limits.TIMER_MAX)
        return .fail(.EINVAL);

    const process = kernel.cThread().owner;
    process.timersLock.lock();

    const timer = &process.timers[timerid];
    // TimerId already free
    if (!timer.inUse) {
        process.timersLock.unlock();
        return .fail(.EINVAL);
    }

    switch (&timer.timerType) {
        .normalTimer => |nTimer| {
            nTimer.remove();
        },
        .cpuTimer => {},
    }

    timer.inUse = false;

    process.timersLock.unlock();

    if (timer.signo >= posix.signal.SIGRTMIN) {
        process.sigData.spinlock.lock();

        // Release a slot if real time
        process.sigData.pendingRTNum -= 1;

        process.sigData.spinlock.unlock();
    }

    return .ok(0);
}

pub fn timer_getoverrun(state : *cpu.CpuState) SysRet {
    const timerid : posix.types.timer_t = state.getArgSys(0).*;

    if (timerid >= posix.limits.TIMER_MAX)
        return .fail(.EINVAL);

    const process = kernel.cThread().owner;

    process.timersLock.lock();
    defer process.timersLock.unlock();

    const timer = &process.timers[timerid];

    if (!timer.inUse)
        return .fail(.EINVAL);

    return .ok(kernel.bin.min(timer.overrun, posix.limits.DELAYTIMER_MAX));
}

pub fn timer_gettime(state : *cpu.CpuState) SysRet {
    const timerid : posix.types.timer_t = state.getArgSys(0).*;
    const value = cast.toPtr(*const allowzero posix.times.itimerspec, state.getArgSys(1).*);

    if (timerid >= posix.limits.TIMER_MAX)
        return .fail(.EINVAL);

    const process = kernel.cThread().owner;

    process.timersLock.lock();

    const timer = process.timers[timerid];

    if (!timer.inUse)
        return .fail(.EINVAL);

    const remaining : u64 = switch (timer.timerType) {
        .cpuTimer => |cTimer| brk: {
            const cur = kernel.pm.process.getCpuTime(cTimer.clockId);

            if (cur <= cTimer.expiration) break :brk 0;

            break :brk cur - cTimer.expiration;
        },
        .normalTimer => |nTimer| brk: {
            if (nTimer.remaining()) |rem| {
                break :brk rem.nsec;
            }
            break :brk 0;
        },
    };

    const reload = timer.reset orelse .zero();

    process.timersLock.unlock();

    var spec : posix.times.itimerspec = undefined;

    spec.it_value = kernel.pm.time.timeToTimespec(remaining);
    spec.it_interval = kernel.pm.time.timeToTimespec(reload);

    if (mem.copyToUser(value, &spec, @sizeOf(posix.times.itimerspec)) != 0)
        return .fail(.EFAULT);

    return .ok(0);
}

pub fn timer_settime(state : *cpu.CpuState) SysRet {
    const timerid : posix.types.timer_t = state.getArgSys(0).*;
    const flags = kernel.bin.convert(i32, state.getArgSys(1).*);
    const value = cast.toPtr(*const allowzero posix.times.itimerspec, state.getArgSys(2).*);
    const ovalue = cast.toPtr(*allowzero posix.times.itimerspec, state.getArgSys(3).*);

    if (timerid >= posix.limits.TIMER_MAX)
        return .fail(.EINVAL);

    var spec : posix.times.itimerspec = undefined;
    if (mem.copyFromUser(&spec, value, @sizeOf(posix.times.itimerspec)) != 0)
        return .fail(.EFAULT);

    if (spec.it_interval.tv_nsec > 1_000_000_000 or spec.it_value.tv_nsec > 1_000_000_000)
        return .fail(.EINVAL);

    const process = kernel.cThread().owner;

    process.timersLock.lock();

    const timer = process.timers[timerid];

    if (!timer.inUse) {
        process.timersLock.unlock();
        return .fail(.EINVAL);
    }

    var specOut : posix.times.itimerspec = undefined;

    if (ovalue != 0) {
        specOut.it_interval = kernel.pm.time.timeToTimespec(timer.reset orelse .zero());

        const leftover = switch (timer.timerType) {
            .normalTimer => |nTimer| nTimer.remaining() orelse .zero(),
            .cpuTimer => |cTimer| brk: {
                break :brk .Nsec(cTimer.expiration - kernel.pm.process.getCpuTime(cTimer.clockId));
            },
        };
        // Remaining
        specOut.it_value = kernel.pm.time.timeToTimespec(leftover);
    }

    const valueTime = kernel.pm.time.timespecToTime(spec.it_value);
    const intervalTime = kernel.pm.time.timespecToTime(spec.it_interval);

    const absTime = kernel.bin.getFlag(posix.times.TIMER_ABSTIME, flags);

    if (valueTime.nsec == 0) {
        timer.armed = false;
    }
    else {
        switch (timer.timerType) {
            .cpuTimer => |*cTimer| {
                if (absTime) {
                    cTimer.expiration = valueTime;
                }
                else {
                    const curTime = kernel.pm.process.getCpuTime(cTimer.clockId);

                    cTimer.expiration = .Nsec(curTime + valueTime.nsec);
                }
            },
            .normalTimer => |*nTimer| {
                _ = nTimer.reset(valueTime, absTime);
            }
        }
    }

    if (intervalTime.nsec != 0)
        timer.reset = intervalTime;

    process.timersLock.unlock();

    if (ovalue != 0 and mem.copyToUser(ovalue, &specOut, @sizeOf(posix.times.itimerspec)) != 0)
        return .fail(.EFAULT);
}
