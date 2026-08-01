const types = @import("types.zig");

pub const CLOCK = enum(u3) {
    NULL = 0,
    /// The identifier of the system-wide clock measuring real time.
    REALTIME = 1,
    /// The identifier for the system-wide monotonic clock, which is defined as a clock measuring real time
    MONOTONIC = 2,
    /// The identifier of the CPU-time clock associated with the process making a clock*() or timer*() function call.
    PROCESS_CPUTIME_ID = 3,
    /// The identifier of the CPU-time clock associated with the thread making a clock*() or timer*() function call.
    THREAD_CPUTIME_ID = 4,
    _,
};

/// Flag for absolute time
pub const TIMER_ABSTIME = 0;

pub const CLOCKS_PER_SEC = 1_000_000_000;

pub fn getClockFromId(clockId : types.clockid_t) CLOCK {
    return @enumFromInt(clockId & 0x7);
}

pub fn getPidFromId(clockId : types.clockid_t) u32 {
    return clockId >> 3;
}

pub fn getTidFromId(clockId : types.clockid_t) u32 {
    return clockId >> 3;
}

pub fn getProcClockFromPid(pid : u32) types.clockid_t {
    return (pid << 3) | @intFromEnum(CLOCK.PROCESS_CPUTIME_ID);
}

pub fn getThrdClockFromTid(tid : u32) types.clockid_t {
    return (tid << 3) | @intFromEnum(CLOCK.THREAD_CPUTIME_ID);
}

pub const timespec = extern struct {
    tv_sec : types.time_t,  // Whole seconds.
    tv_nsec : i64,          // Nanoseconds [0, 999999999].
};

pub const tm = extern struct {
    tm_sec : i32 = 0,       // Seconds [0,60].
    tm_min : i32 = 0,       // Minutes [0,59].
    tm_hour : i32 = 0,      // Hour [0,23].
    tm_mday : i32 = 0,      // Day of month [1,31].
    tm_mon : i32 = 0,       // Month of year [0,11].
    tm_year : i32 = 0,      // Years since 1900.
    tm_wday : i32 = 0,      // Day of week [0,6] (Sunday = 0).
    tm_yday : i32 = 0,      // Day of year [0,365].
    tm_isdst : i32 = 0,     // Daylight Saving flag.
    tm_gmtoff : i64 = 0,    // Seconds east of UTC.
    tm_zone : [*:0]u8 = undefined,  // Timezone abbreviation.
};