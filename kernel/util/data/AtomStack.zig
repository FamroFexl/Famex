const std = @import("std");
const Order = std.builtin.AtomicOrder;
const Op = std.builtin.AtomicRmwOp;

next : ?*@This(),

pub const Node = @This();

pub fn init(stack : *@This()) void {
    stack.next = null;
}

pub fn empty(stack : *@This()) bool {
    return @atomicLoad(?*Node, &stack.next, Order.seq_cst) == null;
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