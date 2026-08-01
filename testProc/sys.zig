const std = @import("std");

const posix = @import("posix");
const SysNum = posix.sysnum.SysNum;

inline fn syscall(number: u64, args: [6]u64) u64 {
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

fn asU64(value: anytype) u64 {
    const T = @TypeOf(value);

    if (T == comptime_int) {
        return @as(u64, value);
    }

    const size = @sizeOf(T);

    var result: u64 = 0;
    @memcpy(
        std.mem.asBytes(&result)[0..size],
        std.mem.asBytes(&value)[0..size],
    );
    return result;
}

fn syscallRet(number : u64, arg0 : anytype, arg1 : anytype, arg2 : anytype, arg3 : anytype, arg4 : anytype, arg5 : anytype) u64 {
    return syscall(number, .{
        asU64(arg0), asU64(arg1), asU64(arg2), asU64(arg3), asU64(arg4), asU64(arg5),
    });
}

fn syscallReg(ret : u64) i32 {
    return @bitCast(@as(u32, @truncate(ret)));
}

pub fn print(comptime str : []const u8, args: anytype) void {
    var buf : [1000]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, str, args) catch {
        const err = "bufPrint overflow\n";
        _ = syscallRet(@intFromEnum(SysNum.PRINT), err[0..].ptr, err.len, 0, 0, 0, 0);
        return;
    };
    _ = syscallRet(@intFromEnum(SysNum.PRINT),out.ptr, out.len, 0, 0, 0, 0);
}

pub fn mmap(addr : *anyopaque, len : u64, prot : posix.mman.PROT, flags : posix.mman.MAP, fildes : i32, off : posix.types.off_t) *anyopaque {
    return @ptrFromInt(syscallRet(@intFromEnum(SysNum.MMAP), addr, len, prot, flags, fildes, off));
}

pub fn sigaction(sig : i32, act : *allowzero posix.signal.sigaction, oact : *allowzero posix.signal.sigaction) i32 {
    return syscallReg(syscallRet(@intFromEnum(SysNum.SIGACTION), sig, act, oact, 0, 0, 0));
}

pub fn sigaltstack(ss : *const allowzero posix.signal.stack_t, oss : *allowzero posix.signal.stack_t) i32 {
    return syscallReg(syscallRet(@intFromEnum(SysNum.SIGALTSTACK), ss, oss, 0, 0, 0, 0));
}

pub fn sigqueue(pid : posix.types.pid_t, signo : i32, value : posix.signal.sigval) i32 {
    return syscallReg(syscallRet(@intFromEnum(SysNum.SIGQUEUE), pid, signo, value, 0, 0, 0));
}

pub fn pthread_sigmask(how : posix.signal.SigSet, set : *const posix.signal.sigset_t, oset : *allowzero posix.signal.sigset_t) i32 {
    return syscallReg(syscallRet(@intFromEnum(SysNum.PTHREAD_SIGMASK), how, set, oset, 0, 0, 0));
}

pub fn sched_yield() i32 {
    _ = syscallRet(@intFromEnum(SysNum.SCHED_YIELD), 0, 0, 0, 0, 0, 0);
    return 0;
}

pub fn clock_nanosleep(clockId : posix.types.clockid_t, flags : i32, rqtp : *posix.times.timespec, rmtp : *posix.times.timespec) i32 {
    return syscallReg(syscallRet(@intFromEnum(SysNum.CLOCK_NANOSLEEP), clockId, flags, rqtp, rmtp, 0, 0));
}

pub fn time(tloc : *allowzero posix.types.time_t) u64 {
    return syscallRet(@intFromEnum(SysNum.TIME), tloc, 0, 0, 0, 0, 0);
}

pub fn alarm(seconds : u32) u32 {
    return @truncate(syscallRet(@intFromEnum(SysNum.ALARM), seconds, 0, 0, 0, 0, 0));
}