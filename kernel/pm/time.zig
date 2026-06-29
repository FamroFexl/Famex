const std = @import("std");

const kernel = @import("kernel");

var LOCAL_TIMER : Timer = undefined;
var SYSTEM_CLOCK : Clock = undefined;
var CALIBRATION_CLOCK : Clock = undefined;

var unixOffset : u64 = undefined;

const TimeUnit = enum(u8) {
    SEC = 0,
    MSEC = 1,
    USEC = 2,
    NSEC = 3,
};

/// Stores and mutates time units
pub const Time = struct {
    nsec : u64,

    pub fn create(unit : TimeUnit, val : u64) @This() {
        var time : @This() = undefined;
        time.set(unit, val);
        return time;
    }

    pub fn get(this : @This(), unit : TimeUnit, ceil : bool) u64 {
        const pow = std.math.pow(u64, 1000, 3 - @intFromEnum(unit));
        return (this.nsec + if (ceil) pow - 1 else 0) / pow;
    }

    pub fn set(this : *@This(), unit : TimeUnit, val : u64) void {
        this.nsec = val * std.math.pow(u64, 1000, 3 - @intFromEnum(unit));
    }

    pub fn dist(this : @This(), other : @This(), unit : TimeUnit, ceil : bool) @This() {
        const between = kernel.bin.dist(this.nsec, other.nsec);
        return get(.{.nsec = between}, unit, ceil);
    }

    pub fn add(this : *@This(), unit : TimeUnit, val : u64) void {
        var in : Time = undefined;
        set(&in, unit, val);
        const overflow = @addWithOverflow(this.nsec, in.nsec);

        std.debug.assert(overflow[1] == 0);

        this.nsec = overflow[0];
    }

    pub fn sub(this : *@This(), unit : TimeUnit, val : u64) void {
        var in : Time = undefined;
        set(&in, unit, val);
        const underflow = @subWithOverflow(this.nsec, in.nsec);

        this.nsec = if (underflow[1] == 1) 0 else underflow[0];
    }
};

const Timer = struct {
    var TIMERS : kernel.List = undefined;

    tps : u64,     // Ticks per second
    get : *const fn (*@This()) u64,
    set : *const fn (*@This(), u64) void,
    global : bool,  // Timer is core-local or system-local
    name : [8]u8,
    link : kernel.List.Node,

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
};

const Clock = struct {
    var CLOCKS : kernel.List = undefined;

    tps : u64,  // Ticks per second
    get : *const fn(*@This()) u64,
    name : [8]u8,
    link : kernel.List.Node,

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
};

