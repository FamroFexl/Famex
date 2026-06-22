const std = @import("std");

/// Bits to bytes
pub fn toBytes(bits : anytype) u64 {
    return (bits + 7) / 8;
}

pub fn setBit(bit : anytype) u64 {
    return @as(u64, 1) << @intCast(bit);
}

pub fn getBit(bit : anytype, bits : anytype) bool {
    return (bits >> bit) & 1 == 1;
}

pub fn getBits(amount : anytype, index : anytype, bits : anytype) u64 {
    return (@as(u64, @intCast(bits)) >> @intCast(index)) & setBits(amount);
}

pub fn setBits(bit : anytype) u64 {
    return setBit(bit) - 1;
}

pub fn getAlign(num : u64) u64 {
    return num & (~num + 1);
}

pub fn alignUp(num : anytype, mul : anytype) u64 {
    const num_typed : u64 = @intCast(num);
    const mul_typed : u64 = @intCast(mul);
    return (num_typed + mul_typed - 1) & ~(mul_typed - 1);
}

pub fn alignDown(num : anytype, mul : anytype) u64 {
    const num_typed : u64 = @intCast(num);
    const mul_typed : u64 = @intCast(mul);
    return num_typed & ~(mul_typed - 1);
}

pub fn alignUpNum(num : anytype, mul : anytype) u64 {
    const num_typed : u64 = @intCast(num);
    const mul_typed : u64 = @intCast(mul);
    return (num_typed + mul_typed - 1) / (mul_typed * mul_typed);
}

pub fn alignDownNum(num : anytype, mul : anytype) u64 {
    const num_typed : u64 = @intCast(num);
    const mul_typed : u64 = @intCast(mul);
    return num_typed - (num_typed % mul_typed);
}

pub fn maxAlignBetween(addr : anytype, limit : anytype) u64 {
    const range : u64 = dist(addr, limit);
    const pow2 : u64 = setBit(63 - @clz(range));
    return min(pow2, getAlign(addr));
}

pub fn roundUpPow2(val : anytype) u64 {
    if (val <= 1) return 1;

    return setBit(64 - @clz(@as(u64, val) - 1));
}

pub fn setFlag(flag : anytype, bin : *u64) void {
    bin.* |= setBit(@as(u6, @intCast(flag)));
}

pub fn clearFlag(flag : anytype, bin : *u64) void {
    bin.* &= ~setBit(@as(u6, @intCast(flag)));
}

pub fn getFlag(flag : anytype, bin : u64) bool {
    return bin >> @as(u6, @intCast(flag)) & 1 == 1;
}

pub fn changeFlag(flag : anytype, bin : *u64, set : bool) void {
    bin.* = (bin.* & ~(1 << flag)) | (set << flag);
}

pub fn min(num1 : anytype, num2: anytype) u64 {
    return if (num1 > num2) num2 else num1;
}

pub fn max(num1 : anytype, num2: anytype) u64 {
    return if (num1 > num2) num1 else num2;
}

pub fn dist(num1 : anytype, num2 : anytype) u64 {
    return if(num1 > num2) num1 - num2 else num2 - num1;
}

pub fn setIfLarger(comptime T: type, current: *T, new_value: T) void {
    if (new_value > current.*) {
        current.* = new_value;
    }
}

pub fn setIfSmaller(comptime T: type, current: *T, new_value: T) void {
    if (new_value < current.*) {
        current.* = new_value;
    }
}

pub fn isZero(val : anytype) bool {
    return std.mem.allEqual(u8, std.mem.asBytes(&val), 0);
}

pub fn ptrCast(comptime T : type, val : *anyopaque) T {
    return @ptrCast(@alignCast(val));
}

pub fn getFlexArray(comptime T : type, comptime O : type, val : *T) [*]O {
    const base: [*]u8 = @ptrCast(val);

    const start = std.mem.alignForward(u64, @sizeOf(T), @alignOf(O));
    const raw = base + start;

    return @ptrCast(@alignCast(raw));
}

pub fn SizedType(comptime size: usize, comptime alignment: u29) type {
    return struct {
        data: [size]u8 align(alignment),
    };
}