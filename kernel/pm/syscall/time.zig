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
        return .fail(posix.errno.EFAULT);
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
    kernel.reschedule();
}

pub fn clock_nanosleep(state : *cpu.CpuState) SysRet {
    const clockId : posix.types.clockid_t = @truncate(state.getArgSys(0).*);
    const flags : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(1).*)));
    const rqtp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(2).*);
    const rmtp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(3).*);

    var timeTill : posix.times.timespec = undefined;
    if (mem.copyFromUser(&timeTill, rqtp, @sizeOf(posix.times.timespec)) != 0)
        return .fail(posix.errno.EFAULT);

    if (timeTill.tv_nsec >= 1000_000_000)
        return .fail(posix.errno.EINVAL);

    const newTime = kernel.pm.time.timespecToTime(timeTill);

    const clock : posix.times.CLOCK = @enumFromInt(clockId);
    const curTime = switch (clock) {
        .MONOTONIC => kernel.getMonoClock(),
        .REALTIME =>  kernel.getUnixClock(),
        .PROCESS_CPUTIME_ID, .THREAD_CPUTIME_ID => return .fail(posix.errno.ENOTSUP),
        else => return .fail(posix.errno.EINVAL),
    };

    const thread = kernel.cThread();

    var wakeEvent : ThreadWake = .{
        .thread = thread,
        .event = kernel.TimerEvent.create(
            switch(clock) { .MONOTONIC => .MONOTONIC, .REALTIME => .UNIX, else => undefined},
            .zero(),
            threadWake,
        ),
    };

    if (kernel.bin.getFlag(posix.times.TIMER_ABSTIME, kernel.bin.convert(u64, flags))) {
        if (newTime.nsec <= curTime.nsec)
            return .ok(0);

        wakeEvent.event.reset(newTime, true);
    }
    else {
        wakeEvent.event.reset(newTime, false);
    }

    thread.spinlock.lock();
    thread.state = .INTERRUPTABLE;
    thread.spinlock.unlock();

    kernel.irqSave();
    thread.sleep();
    kernel.irqRestore();

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
                    return .fail(posix.errno.EFAULT);
            }
        }

        return .fail(posix.errno.EINTR);
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
        else => return .fail(posix.errno.EINVAL),
    };

    if (mem.copyToUser(res, cast.toPtr(*anyopaque, &out), @sizeOf(posix.times.timespec)) > 0)
        return .fail(posix.errno.EFAULT);

    return .ok(0);
}

pub fn clock_getcpuclockid(state : *cpu.CpuState) SysRet {
    const pid : u32 = @truncate(state.getArgSys(0).*);
    const clockId = cast.toPtr(*allowzero posix.types.clockid_t, state.getArgSys(1).*);

    if (pid != kernel.cThread().owner.pid)
        return .fail(posix.errno.EPERM);

    var out : posix.types.clockid_t = undefined;
    if (pid == 0) {
        out = posix.times.getProcClockFromPid(@intCast(kernel.cThread().owner.pid));
    }
    else {
        _ = kernel.pids.get(pid) orelse return .fail(posix.errno.ESRCH);
        out = posix.times.getProcClockFromPid(pid);
    }

    if (mem.copyToUser(clockId, &out, @sizeOf(posix.types.clockid_t)) > 0) {
        return .fail(posix.errno.EFAULT);
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
            const process = cast.toPtr(*kernel.Process, kernel.pids.get(pid) orelse return .fail(posix.errno.EINVAL));

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
            const thread = cast.toPtr(*kernel.Thread, kernel.tids.find(tid) orelse return .fail(posix.errno.EINVAL));

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
        .NULL, _ => return .fail(posix.errno.EINVAL),
    };

    const out = kernel.pm.time.timeToTimespec(total);

    if (mem.copyToUser(tp, cast.toPtr(*anyopaque, &out), @sizeOf(posix.times.timespec)) > 0)
        return .fail(posix.errno.EFAULT);

    return .ok(0);
}

pub fn clock_settime(state : *cpu.CpuState) SysRet {
    const clockId : posix.types.clockid_t = @truncate(state.getArgSys(0).*);
    const tp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(1).*);

    if (kernel.cThread().owner.creds.euid != 0)
        return .fail(posix.errno.EPERM);

    var in : posix.times.timespec = undefined;
    if (mem.copyFromUser(&in, tp, @sizeOf(posix.times.timespec)) > 0)
        return .fail(posix.errno.EFAULT);

    if (in.tv_nsec >= kernel.Time.Sec(100).nsec)
        return .fail(posix.errno.EINVAL);

    switch (posix.times.getClockFromId(clockId)) {
        .REALTIME => kernel.pm.time.setUnixClock(kernel.pm.time.timespecToTime(in)),
        .PROCESS_CPUTIME_ID, .THREAD_CPUTIME_ID => return .ok(0),    // These can't be set, but can't fail
        else => return .fail(posix.errno.EINVAL),
    }

    return .ok(0);
}

pub fn timer_create(state : *cpu.CpuState) SysRet {
    const clockid : posix.types.clockid_t = kernel.bin.convert(u32, state.getArgSys(0).*);
    const evp = cast.toPtr(*allowzero posix.signal.sigevent, state.getArgSys(1).*);
    const timerid = cast.toPtr(*allowzero posix.types.timer_t, state.getArgSys(2).*);
    _ = clockid;
    _ = evp;
    _ = timerid;
}
