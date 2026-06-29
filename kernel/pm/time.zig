const std = @import("std");

const kernel = @import("kernel");

var LOCAL_TIMER : Timer = undefined;
var SYSTEM_CLOCK : Clock = undefined;
var CALIBRATION_CLOCK : Clock = undefined;

var unixOffset : u64 = undefined;

/// Stores and mutates time units
pub const TimeUnit = union(enum) {
    S : u64,
    MS : u64,
    US : u64,
    NS : u64,

    const Tag = @typeInfo(@This()).@"union".tag_type.?;

    fn convert(this : @This(), to : Tag, ceil : bool) u64 {
        const diff : i8 = @intFromEnum(to) - @intFromEnum(@as(Tag, this));

        switch (this) { inline else => |val| {
            if (diff > 0) {
                const pow = std.math.pow(u64, 1000, @intCast(diff));

                return val * pow;
            }
            else {
                const pow = std.math.pow(u64, 1000, @intCast(-diff));

                return (val + if (ceil) pow - 1 else 0) / pow;
            }
        }}
    }

    pub fn get(this : @This()) u64 {
        return switch (this) { inline else => |val| val};
    }

    /// Add to the time
    pub fn add(this : *@This(), unit : TimeUnit, ceil : bool) void {
        const old = get(this.*);
        const tape = convert(unit, @as(Tag, this.*), ceil);

        const overflow = @addWithOverflow(old, tape);
        std.debug.assert(overflow[1] == 0);

        const new = overflow[0];

        switch (this.*) {
            .S => this.* = .{ .S = new },
            .MS => this.* = .{ .MS = new },
            .US => this.* = .{ .US = new },
            .NS => this.* = .{ .NS = new },
        }
    }

    /// Subtract from the time
    pub fn sub(this : *@This(), unit : TimeUnit, ceil : bool) void {
        const old = get(this.*);
        const snip = convert(unit, @as(Tag, this.*), ceil);

        const underflow = @subWithOverflow(old, snip);
        const new = if (underflow[1] == 1) 0 else underflow[0];

        switch (this.*) {
            .S => this.* = .{ .S = new },
            .MS => this.* = .{ .MS = new },
            .US => this.* = .{ .US = new },
            .NS => this.* = .{ .NS = new },
        }
    }

    /// Convert to seconds
    pub fn s(this : @This(), ceil : bool) TimeUnit {
        return TimeUnit{.S = this.convert(.S, ceil)};
    }

    /// Convert to milliseconds
    pub fn ms(this : @This(), ceil : bool) TimeUnit {
        return TimeUnit{.MS = this.convert(.MS, ceil)};
    }

    /// Convert to microseconds
    pub fn us(this : @This(), ceil : bool) TimeUnit {
        return TimeUnit{.US = this.convert(.US, ceil)};
    }

    /// Convert to nanoseconds
    pub fn ns(this : @This(), ceil : bool) TimeUnit {
        return TimeUnit{.NS = this.convert(.NS, ceil)};
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

