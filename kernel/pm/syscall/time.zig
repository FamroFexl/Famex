const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const cpu = @import("arch").cpu;

const SysRet = @import("syscall.zig").SysRet;

const posix = @import("lib").posix;

pub fn time(state : *cpu.CpuState) SysRet {
    const tloc = cast.toPtr(*allowzero posix.types.time_t, state.getArgSys(0).*);

    const out = kernel.getUnixClock().get(.SEC, false);

    _ = cpu.copyToUser(tloc, cast.toPtr(*anyopaque, &out), @sizeOf(posix.types.time_t));

    return .ok(out);
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

    if (cpu.copyToUser(res, cast.toPtr(*anyopaque, &out), @sizeOf(posix.times.timespec)) > 0)
        return .fail(posix.errno.EFAULT);

    return .ok(0);
}

pub fn clock_getcpuclockid(state : *cpu.CpuState) SysRet {
    const pid : u32 = @truncate(state.getArgSys(0).*);
    const clockId = cast.toPtr(*allowzero posix.types.clockid_t, state.getArgSys(1).*);

    // if (no perms) ereturn(EPERM);

    var out : posix.types.clockid_t = undefined;
    if (pid == 0) {
        out = posix.times.getProcClockFromPid(@intCast(kernel.cThread().owner.pid));
    }
    else {
        _ = kernel.pids.get(pid) orelse return .fail(posix.errno.ESRCH);
        out = posix.times.getProcClockFromPid(pid);
    }

    if (cpu.copyToUser(clockId, &out, @sizeOf(posix.types.clockid_t)) > 0) {
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

            // TODO not contention safe
            var iter = process.threads.iterator();
            while(iter.next()) |next| {
                const thread : *kernel.Thread = @fieldParentPtr("link", next);

                thread.timeLock.readLock();
                defer thread.timeLock.readUnlock();

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

            thread.timeLock.readLock();
            defer thread.timeLock.readUnlock();

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

    if (cpu.copyToUser(tp, cast.toPtr(*anyopaque, &out), @sizeOf(posix.times.timespec)) > 0)
        return .fail(posix.errno.EFAULT);

    return .ok(0);
}

pub fn clock_settime(state : *cpu.CpuState) SysRet {
    const clockId : posix.types.clockid_t = @truncate(state.getArgSys(0).*);
    const tp = cast.toPtr(*allowzero posix.times.timespec, state.getArgSys(1).*);

    if (kernel.cThread().owner.creds.euid != 0)
        return .fail(posix.errno.EPERM);

    var in : posix.times.timespec = undefined;
    if (cpu.copyFromUser(&in, tp, @sizeOf(posix.times.timespec)) > 0)
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
