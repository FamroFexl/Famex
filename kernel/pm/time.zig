const std = @import("std");

const kernel = @import("kernel");
const lib = @import("lib");

pub var CALIBRATION_CLOCK : Clock = undefined;
pub var SYSTEM_CLOCK : Clock = undefined;
pub var LOCAL_TIMER : Timer = undefined;

/// Unix time offset from monotonic
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

const Timer = struct {
    var TIMERS : kernel.List = undefined;

    tps : u64,     // Ticks per second
    getRaw : *const fn (*@This()) u64,
    setRaw : *const fn (*@This(), u64) void,
    max : u64,      // Max value the timer can store
    name : [8]u8,
    link : kernel.List.Node,

    pub fn calibrate(this : *@This(), duration : Time) void {
        const start = this.max;

        const calStart = CALIBRATION_CLOCK.get();
        this.set(start);

        while (CALIBRATION_CLOCK.get() < calStart + duration.nsec) {}

        const end = this.get();

        this.set(.{.nsec = 0});

        this.tps = (1_000_000_000 * (start - end)) / duration;
    }

    pub fn byName(name : []const u8) ?*Timer {
        var next = TIMERS.next;
        while (next != &TIMERS) {
            const timer : *Timer = @fieldParentPtr("link", next);
            if (std.mem.eql(u8, name, timer.name)) {
                return timer;
            }
            next = next.next;
        }

        return null;
    }

    pub fn set(this : *@This(), time : Time) void {
        this.setRaw(@intCast((@as(u128, this.tps) * @as(u128, time.nsec) + 500_000_000) / 1_000_000_000));
    }

    pub fn get(this : *@This()) Time {
        return .{.nsec = @as(u64, (@as(u128, @intCast(this.getRaw())) * 1_000_000_000) / this.tps)};
    }
};

const Clock = struct {
    var CLOCKS : kernel.List = undefined;

    tps : u64,  // Ticks per second
    getRaw : *const fn(*@This()) u64,
    name : [8]u8,
    link : kernel.List.Node,

    pub fn calibrate(this : *@This(), duration : Time) void {
        const calStart = CALIBRATION_CLOCK.get();
        const start = this.get();

        while (CALIBRATION_CLOCK.get() < calStart + duration.nsec) {}

        const end = this.get();

        this.tps = (1_000_000_000 * (start - end)) / duration;
    }

    pub fn byName(name : []const u8) ?*Timer {
        var next = CLOCKS.next;
        while (next != &CLOCKS) {
            const timer : *Timer = @fieldParentPtr("link", next);
            if (std.mem.eql(u8, name, timer.name)) {
                return timer;
            }
            next = next.next;
        }

        return null;
    }

    pub fn get(this : *@This()) Time {
        return .{.nsec = @intCast((@as(u128, @intCast(this.getRaw())) * 1_000_000_000) / this.tps)};
    }
};

/// Get monotonic clock
pub fn getMonoClock() Time {
    return SYSTEM_CLOCK.get();
}

/// Get unix time (can change)
pub fn getUnixClock() Time {
    return getMonoClock().add(.NSEC, unixOffset.load(.acquire));
}

pub fn setUnixClock(time : Time) void {
    const monoTime = getMonoClock();
    const offset : i64 = if (time.nsec > monoTime.nsec) -(@as(i64, @intCast(monoTime.nsec - time.nsec))) else @as(i64, @intCast(time.nsec - monoTime.nsec));
    unixOffset.store(offset, .acquire);
}

pub fn setLocalTimer(time : Time) void {
    LOCAL_TIMER.set(time);
}

pub fn getLocalTimer() Time {
    return LOCAL_TIMER.get();
}

const TimerTree = lib.linux.RBTree(TimerEvent, "link", "expiration", true);

var timerLock = kernel.PerCpuStat(kernel.Spinlock);
var monoTimers = kernel.PerCpuStat(TimerTree);
var unixTimers = kernel.PerCpuStat(TimerTree);

/// Set the local timer
fn timerSet() void {
    var time : u64 = std.math.maxInt(u64);

    const spinlock = timerLock.getLocal();
    spinlock.lock();
    defer spinlock.unlock();

    var node : ?*TimerTree.Node = unixTimers.getLocal().first();
    if (node) |n| {
        kernel.bin.setIfSmaller(u64, &time, n.holder().expiration.nsec - unixOffset.load(.acquire));
    }

    node = monoTimers.getLocal().first();
    if (node) |n| {
        kernel.bin.setIfSmaller(u64, &time, n.holder().expiration.nsec);
    }

    // No events are waiting. There is no need to set the local timer
    if (node == null)
        return;

    setLocalTimer(time - getMonoClock().nsec);
}

pub const TimerEvent = struct {
    expiration : Time,                          // Time the event expires
    callback : *const fn (*@This()) void,       // Function to call on expiration
    cpuId : u8,                                 // Which cpu it was added to
    tag : Type,                                 // Timer is unix/realtime or monotonic
    slack : Time,                               // How much can the timer be delayed by for purposes of reshuffling
    link : TimerTree.Node = undefined,

    const Type = enum {
        MONOTONIC,
        UNIX
    };

    pub fn init(this : *@This(), tag : Type, slack : Time, callback : *const fn (*@This()) void) void {
        this.tag = tag;
        this.slack = slack;
        this.callback = callback;
        this.cpuId = kernel.getCpuId();
        this.link.clear();
    }

    /// Set or reset an initialized timer with relative or absolute time
    pub fn reset(this : *@This(), expiration : Time, absolute : bool) void {

        const newExpiration =
            if (absolute) expiration.nsec
            else
            switch (this.tag) {
                .MONOTONIC => expiration.nsec + getMonoClock().nsec,
                .UNIX => expiration.nsec + getUnixClock().nsec,
            };

        // Already expired
        if (this.tag == .UNIX and newExpiration <= getUnixClock().nsec) {
            this.callback();
            return;
        }

        const tree : *TimerTree = switch (this.tag) {
            .MONOTONIC => monoTimers.getLocal(),
            .UNIX => unixTimers.getLocal(),
        };

        timerLock.lock();
        defer timerLock.unlock();

        // Delete the node if it exists
        if (!this.link.empty())
            tree.erase(&this.link);

        this.expiration = expiration;

        // Coalesce timers together within slack time
        const next = tree.findAfter(this.expiration);

        if (next) |n| {
            const nextEvent = n.holder();
            if (this.expiration + this.slack >= nextEvent.expiration)
                this.expiration = nextEvent.expiration;
        }

        tree.add(&this.link);

        if (tree.first() == &this.link)
            timerSet();
    }

    pub fn remove(this : *@This()) void {
        const tree : *TimerTree = switch (this.tag) {
            .MONOTONIC => monoTimers.getLocal(),
            .UNIX => unixTimers.getLocal(),
        };

        timerLock.lock();

        tree.erase(&this.link);

        timerLock.unlock();

        this.link.clear();
    }

    /// Timer event handler for IRQs
    pub fn handler() void {
        const time = getMonoClock();

        var temp : kernel.Stack = .{};

        const offset = unixOffset.load(.acquire);

        var nextTime : u64 = std.math.maxInt(u64);

        const mTimers = monoTimers.getLocal();
        const uTimers = unixTimers.getLocal();

        const spinlock = timerLock.getLocal();
        spinlock.lock();

        // Get monotonic timers
        while (true) {
            const node = mTimers.first() orelse break;
            const event : *TimerEvent = @fieldParentPtr("link", node);

            if (event.expiration > time) {
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

            const expiration = event.expiration - offset;

            if (expiration > time) {
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
            const node = temp.pop() orelse break;
            const event : *TimerEvent = @fieldParentPtr("link", node);

            event.callback();

            const rbNode : *TimerTree.Node = @ptrCast(node);
            rbNode.clear();
        }

        if (nextTime != std.math.maxInt(u64))
            setLocalTimer(nextTime - time);
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




