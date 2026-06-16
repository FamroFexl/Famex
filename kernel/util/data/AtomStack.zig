const std = @import("std");
const Order = std.builtin.AtomicOrder;
const Op = std.builtin.AtomicRmwOp;

next : std.atomic.Value(?*@This()),

pub const Node = @This();

pub fn init(stack : *@This()) void {
    stack.next = .init(null);
}

pub fn empty(stack : *@This()) bool {
    return stack.next.load(.seq_cst) == null;
}

pub fn push(stack : *@This(), node : *Node) void {
    _ = stack;
    _ = node;
}

pub fn pop(stack : *@This()) ?*Node {
    _ = stack;
}

pub fn drain(stack : *@This()) ?*Node {
    return stack.next.rmw(.Xchg, null, .acquire);
}