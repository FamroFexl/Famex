pub inline fn @"u128"(val : anytype) u128 {
    return @intCast(val);
}

pub inline fn @"u64"(val : anytype) u64 {
    return @intCast(val);
}

pub inline fn @"u32"(val : anytype) u32 {
    return @intCast(val);
}

pub inline fn @"u16"(val : anytype) u16 {
    return @intCast(val);
}

pub inline fn @"u8"(val : anytype) u8 {
    return @intCast(val);
}

pub inline fn @"i128"(val : anytype) i128 {
    return @intCast(val);
}

pub inline fn @"i64"(val : anytype) i64 {
    return @intCast(val);
}

pub inline fn @"i32"(val : anytype) i32 {
    return @intCast(val);
}

pub inline fn @"i16"(val : anytype) i16 {
    return @intCast(val);
}

pub inline fn @"i8"(val : anytype) u32 {
    return @intCast(val);
}

pub inline fn toInt(val : anytype) u64 {
    return switch(@typeInfo(@TypeOf(val))) {
        .pointer => @intFromPtr(val),
        .int => @intCast(val),
        .@"enum" => @intFromEnum(val),
        .@"bool" => @intFromBool(val),
        else => @panic("Only ints, pointers, enums, and bools supported!"),
    };
}

pub inline fn toPtr(comptime T : type, val : anytype) T {
    return switch(@typeInfo(@TypeOf(val))) {
        .pointer => @ptrCast(@alignCast(@constCast(val))),
        .int => @ptrFromInt(val),
        else => @panic("Only ints and pointers supported!"),
    };
}

pub inline fn bit(comptime T : type, val : anytype) T {
    return @bitCast(val);
}