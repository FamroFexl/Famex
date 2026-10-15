const std = @import("std");

count : std.atomic.Value(u32),

pub fn create() @This() {
    return .{.count = .{.raw = 1}};
}

pub fn init(this : *@This()) void {
    this.* = create();
}

pub fn incr(this : *@This()) void {
    this.count.fetchAdd(1, .release);
}

/// Returns true if the count becomes 0
pub fn decrAndTest(this : *@This()) void {
    const out = this.count.fetchSub(1, .release);

    if (out == 0)
        @panic("RefCount Decrement underflowed!");

    if (out == 1)
        return true;

    return false;
}

pub fn decr(this : *@This()) void {
    _ = this.decrAndTest();
}