const std = @import("std");

next : ?*@This(),

pub const Node = @This();

pub fn init(stack : *@This()) void {
    stack.next = null;
}

pub fn empty(stack : *@This()) bool {
    return stack.next == null;
}

pub fn push(stack : *@This(), node : *Node) void {
    node.next = stack.next;
    stack.next = node;
}

pub fn pop(stack : *@This()) ?*Node {
    const node = stack.next;
    if(node == null) return null;

    stack.next = node.?.next;
    return node;
}

pub fn drain(stack : *@This()) ?*Node {
    const node = stack.next;
    stack.next = null;

    return node;
}

pub fn peek(stack : *@This()) *Node {
    return stack.next;
}
