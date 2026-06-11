const std = @import("std");

next : ?*@This(),

pub const Node = @This();

pub fn init(stack : *@This()) void {
    stack.next = null;
}

pub fn empty(stack : *@This()) bool {
    _ = stack;
}

pub fn push(stack : *@This(), node : *Node) void {
    _ = stack;
    _ = node;
}

pub fn pop(stack : *@This()) *Node {
    _ = stack;
}

pub fn drain(stack : *@This()) *Node {
    return @atomicRmw(?*Node, &stack.next, std.builtin.AtomicRmwOp.Xchg, null, std.builtin.AtomicOrder.acquire);
}