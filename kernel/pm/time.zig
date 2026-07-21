const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const lib = @import("lib");

/// Used to calibrate clocks and timers
pub var CALIBRATION_CLOCK : *Clock = undefined;
pub var SYSTEM_CLOCK : *Clock = undefined;
pub var LOCAL_TIMER : *Timer = undefined;

/// Unix time offset from monotonic in nanoseconds
var unixOffset : std.atomic.Value(i64) = undefined;

/// Stores and mutates time units
pub const Time = struct {
    /// Nanoseconds
    nsec : u64,

    const TimeUnit = enum(u8) {
        SEC = 0,
        MSEC = 1,
        USEC = 2,
        NSEC = 3,
    };

    pub fn create(unit : TimeUnit, val : u64) @This() {
        var time : @This() = undefined;
        time.set(unit, val);
        return time;
    }

    pub fn zero() @This() {
        return .{.nsec = 0};
    }

    pub fn Sec(val : u64) @This() {
        return create(.SEC, val);
    }

    pub fn Msec(val : u64) @This() {
        return create(.MSEC, val);
    }

    pub fn Usec(val : u64) @This() {
        return create(.USEC, val);
    }

    pub fn Nsec(val : u64) @This() {
        return create(.NSEC, val);
    }

    pub fn get(this : @This(), unit : TimeUnit, ceil : bool) u64 {
        const pow = std.math.pow(u64, 1000, 3 - @intFromEnum(unit));
        return (this.nsec + if (ceil) pow - 1 else 0) / pow;
    }

    pub fn set(this : *@This(), unit : TimeUnit, val : u64) void {
        this.nsec = val * std.math.pow(u64, 1000, 3 - @intFromEnum(unit));
    }

    pub fn dist(this : @This(), other : @This()) @This() {
        const between = kernel.bin.dist(this.nsec, other.nsec);
        return .{.nsec = between};
    }

    pub fn add(this : *@This(), unit : TimeUnit, val : u64) void {
        var in : @This() = undefined;
        set(&in, unit, val);
        const overflow = @addWithOverflow(this.nsec, in.nsec);

        std.debug.assert(overflow[1] == 0);

        this.nsec = overflow[0];
    }

    pub fn sub(this : *@This(), unit : TimeUnit, val : u64) void {
        var in : @This() = undefined;
        set(&in, unit, val);
        const underflow = @subWithOverflow(this.nsec, in.nsec);

        this.nsec = if (underflow[1] == 1) 0 else underflow[0];
    }
};

pub const daysInMonth : [12]u8 = .{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

pub fn isLeapYear(year : anytype) bool {
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
}

pub fn dayOfYear(day : anytype, month : anytype, year : anytype) u16 {
    var dayOut : u16 = day - 1;
    for (0..month) |i| {
        dayOut += daysInMonth[i];
    }

    // Leap day
    if (isLeapYear(year) and month > 2) {
        dayOut += 1;
    }

    return dayOut;
}

pub fn daysFromEpoch(year : anytype) u64 {
    if (year < 1970) @panic("Cannot calculate epoch! Year is less than 1970!");

    var days : u64 = 0;
    for (1970..@intCast(year)) |i| {
        days += if (isLeapYear(i)) 366 else 365;
    }

    return days;
}

pub fn validTimespec(tm : lib.posix.times.tm) bool {
    if (tm.tm_sec < 0 or tm.tm_sec > 60 or
        tm.tm_min < 0 or tm.tm_min > 59 or
        tm.tm_hour < 0 or tm.tm_hour > 23 or
        tm.tm_wday < 0 or tm.tm_wday > 6 or
        tm.tm_yday < 0 or tm.tm_yday > 365 or
        tm.tm_gmtoff < 0 or tm.tm_gmtoff > 50400 or
        tm.tm_isdst < 0
    )
        return false;
    return true;
}

pub fn defaultTimespec() lib.posix.times.tm {
    // Default Time: 1970-01-01T00:00:00
    return .{
        .tm_year = 70,
        .tm_mon = 1,
    };
}

pub fn timeToUnix(tm : lib.posix.times.tm) Time {
    var seconds : u64 = 0;
    seconds += cast.toInt(tm.tm_sec);
    seconds += cast.toInt(tm.tm_min * 60);
    seconds += cast.toInt(tm.tm_hour * 3600);
    seconds += 86400 * (daysFromEpoch(cast.toInt(tm.tm_year) + 1900) + cast.toInt(tm.tm_yday));

    return .Sec(@intCast(seconds));
}

// TODO implement when we need to set RTC
pub fn unixToTime(time : Time) lib.posix.times.tm {
    const seconds = time.get(.SEC, false);
    _ = seconds;

    return defaultTimespec();
}

pub const Timer = struct {
    pub var TIMERS : kernel.List = undefined;

    tps : u64,     // Ticks per second
    getRaw : *const fn (*@This()) u64,
    setRaw : *const fn (*@This(), u64) void,
    max : u64,      // Max value the timer can store
    name : [8]u8,
    local : bool = false,   // Is local timer
    link : kernel.List.Node,

    pub fn calibrate(this : *@This(), duration : Time) void {
        const start = this.max;

        const calStart = CALIBRATION_CLOCK.get();

        this.setRaw(this, start);

        while (CALIBRATION_CLOCK.get().nsec - calStart.nsec < duration.nsec) {}

        const end = this.getRaw(this);

        this.setRaw(this, 0);

        this.tps = (1_000_000_000 * (start - end)) / duration.nsec;
    }

    pub fn byName(name : []const u8) ?*@This() {
        var next = TIMERS.next;
        while (next != &TIMERS) {
            const timer : *@This() = @fieldParentPtr("link", next);
            if (std.mem.eql(u8, name, timer.name[0..name.len])) {
                return timer;
            }
            next = next.next;
        }

        return null;
    }

    pub fn set(this : *@This(), time : Time) void {
        const ticks = cast.u64((cast.u128(this.tps) * cast.u128(time.nsec) + 500_000_000) / 1_000_000_000);

        if (ticks > this.max)
            @panic("Timer set to longer than max can store!");
        this.setRaw(this, ticks);
    }

    pub fn get(this : *@This()) Time {
        return .Nsec(cast.u64(cast.u128(this.getRaw(this)) * 1_000_000_000) / this.tps);
    }
};

pub const Clock = struct {
    pub var CLOCKS : kernel.List = undefined;

    tps : u64,  // Ticks per second
    getRaw : *const fn(*@This()) u64,
    setRaw : *const fn (*@This(), u64) void,
    name : [8]u8,
    link : kernel.List.Node,

    pub fn calibrate(this : *@This(), duration : Time) void {
        const calStart = CALIBRATION_CLOCK.get();
        const start = this.getRaw(this);

        while (CALIBRATION_CLOCK.get().nsec - calStart.nsec < duration.nsec) {}

        const end = this.getRaw(this);

        this.tps = (1_000_000_000 * (start - end)) / duration.nsec;
    }

    pub fn byName(name : []const u8) ?*@This() {
        var next = CLOCKS.next;
        while (next != &CLOCKS) {
            const timer : *@This() = @fieldParentPtr("link", next);
            if (std.mem.eql(u8, name, timer.name[0..name.len])) {
                return timer;
            }
            next = next.next;
        }

        return null;
    }

    pub fn get(this : *@This()) Time {
        return .Nsec(cast.u64(cast.u128(this.getRaw(this) * 1_000_000_000) / this.tps));
    }
};

/// Get monotonic clock
pub fn getMonoClock() Time {
    return SYSTEM_CLOCK.get();
}

/// Get unix time (can change)
pub fn getUnixClock() Time {
    return .Nsec(cast.u64(cast.i128(getMonoClock().nsec) + cast.i128(unixOffset.load(.acquire))));
}

pub fn setUnixClock(time : Time) void {
    const monoTime = getMonoClock();
    const offset : i64 = if (time.nsec < monoTime.nsec) -cast.i64(monoTime.nsec - time.nsec) else cast.i64(time.nsec - monoTime.nsec);
    unixOffset.store(offset, .release);
}

pub fn setLocalTimer(time : Time) void {
    LOCAL_TIMER.set(time);
}

pub fn getLocalTimer() Time {
    return LOCAL_TIMER.get();
}

const TimerTree = lib.linux.RBTree(TimerEvent, "link", "expiration", true);

const timerLock = kernel.PerCpuStat(kernel.Spinlock, opaque {});
const monoTimers = kernel.PerCpuStat(TimerTree, opaque {});
const unixTimers = kernel.PerCpuStat(TimerTree, opaque {});

pub const TimerEvent = struct {
    expiration : u64,                          // Time the event expires
    callback : *const fn (*@This()) void,       // Function to call on expiration
    cpuId : u8 = undefined,                     // Which cpu it was added to
    tag : Type,                                 // Timer is unix/realtime or monotonic
    slack : u64,                               // How much can the timer be delayed by for purposes of reshuffling
    link : TimerTree.Node = .{},

    const Type = enum {
        MONOTONIC,
        UNIX
    };

    pub fn init(this : *@This(), tag : Type, slack : Time, callback : *const fn (*@This()) void) void {
        this.tag = tag;
        this.slack = slack.nsec;
        this.callback = callback;
    }

    pub fn create(tag : Type, slack : Time, callback : *const fn (*@This()) void) @This() {
        return .{
            .tag = tag,
            .slack = slack,
            .callback = callback,
        };
    }

    /// Set or reset an initialized timer with relative or absolute time
    pub fn reset(this : *@This(), expiration : Time, absolute : bool) void {
        this.cpuId = kernel.getCpuId();

        const curTime = switch (this.tag) {
            .MONOTONIC => getMonoClock().nsec,
            .UNIX => getUnixClock().nsec,
        };

        const newExpiration = expiration.nsec + if (absolute) 0 else curTime;

        // Already expired
        if (absolute and newExpiration <= curTime) {
            this.callback(this);
            return;
        }

        const tree : *TimerTree = switch (this.tag) {
            .MONOTONIC => monoTimers.getLocal(),
            .UNIX => unixTimers.getLocal(),
        };

        const spinlock = timerLock.getLocal();
        spinlock.lock();

        // Delete the node if it exists
        if (!this.link.empty())
            tree.erase(&this.link);

        this.expiration = expiration.nsec;

        // Coalesce timers together within slack time
        const next = tree.findAfter(this.expiration);

        if (next) |n| {
            const nextEvent = n.holder();
            if (this.expiration + this.slack >= nextEvent.expiration)
                this.expiration = nextEvent.expiration;
        }

        tree.add(&this.link);

        if (tree.first() != &this.link) {
            spinlock.unlock();
            return;
        }

        var time : u64 = std.math.maxInt(u64);
        var node : ?*TimerTree.Node = unixTimers.getLocal().first();
        if (node) |n| {
            time = @intCast(@as(i128, n.holder().expiration) - @as(i128, unixOffset.load(.acquire)));
        }

        node = monoTimers.getLocal().first();
        if (node) |n| {
            kernel.bin.setIfSmaller(u64, &time, n.holder().expiration);
        }

        spinlock.unlock();

        // No events are waiting. There is no need to set the local timer
        if (node == null) {
            return;
        }

        setLocalTimer(.Nsec(time - getMonoClock().nsec));
    }

    pub fn remove(this : *@This()) void {
        const tree : *TimerTree = switch (this.tag) {
            .MONOTONIC => monoTimers.getLocal(),
            .UNIX => unixTimers.getLocal(),
        };

        const spinlock = timerLock.getLocal();

        {
            spinlock.lock();
            defer spinlock.unlock();

            tree.erase(&this.link);
        }

        this.link.clear();
    }

    /// Timer event handler for IRQs
    pub fn handler() void {
        const time = getMonoClock();

        var temp : kernel.Stack = .{};

        const offset = unixOffset.load(.acquire);

        var nextTime : u64 = std.math.maxInt(u64);

        const uTimers = unixTimers.getLocal();
        const mTimers = monoTimers.getLocal();

        const spinlock = timerLock.getLocal();
        spinlock.lock();

        // Get monotonic timers
        while (true) {
            const node = mTimers.first() orelse break;
            const event : *TimerEvent = @fieldParentPtr("link", node);

            if (event.expiration > time.nsec) {
                nextTime = event.expiration;
                break;
            }

            mTimers.erase(node);

            // We use this element as a temporary stack node
            temp.push(@ptrCast(node));
        }

        // Get realtime timers
        while (true) {
            const node = uTimers.first() orelse break;
            const event : *TimerEvent = @fieldParentPtr("link", node);

            const expiration = cast.u64(cast.i128(event.expiration) - cast.i128(offset));

            if (expiration > time.nsec) {
                if (nextTime > expiration)
                    nextTime = expiration;
                break;
            }

            uTimers.erase(node);

            // We use this element as a temporary stack node
            temp.push(@ptrCast(node));
        }

        spinlock.unlock();

        // Execute all callbacks outside the spinlock
        while (true) {
            const node = cast.toPtr(*TimerTree.Node, temp.pop() orelse break);
            const event : *TimerEvent = @fieldParentPtr("link", node);

            event.callback(event);

            const rbNode : *TimerTree.Node = @ptrCast(node);
            rbNode.clear();
        }

        if (nextTime != std.math.maxInt(u64))
            setLocalTimer(.Nsec(nextTime - time.nsec));
    }
};

pub fn setup() void {
    Timer.TIMERS.init();
    Clock.CLOCKS.init();

    for (0..kernel.CPU_FEATURES.NUM_CPU_CORES) |i| {
        monoTimers.getGlobal(i).init();
        unixTimers.getGlobal(i).init();
        timerLock.getGlobal(i).init();
    }
}




