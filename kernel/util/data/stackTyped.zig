const std = @import("std");

pub fn StackTyped(comptime T : type, comptime linkField : []const u8) type {
    return struct {
        next : ?*@This() = null,

        pub const Node = @This();

        pub fn init(stack : *@This()) void {
            stack.next = null;
        }

        pub fn empty(stack : *@This()) bool {
            return stack.next == null;
        }

        fn getLink(node : *T) *Node {
            return &@field(node, linkField);
        }

        fn getNode(link : *Node) *T {
            return @fieldParentPtr(linkField, link);
        }

        pub fn push(stack : *@This(), node : *T) void {
            const link = getLink(node);
            link.next = stack.next;
            stack.next = link;
        }

        pub fn pop(stack : *@This()) ?*T {
            const node = stack.next orelse return null;

            stack.next = node.next;
            return getNode(node);
        }

        pub fn drain(stack : *@This()) ?*T {
            const node = stack.next;
            stack.next = null;

            if (!node) return null;

            return getNode(node);
        }

        pub fn peek(stack : *@This()) *T {
            return getNode(stack.next);
        }
    };
}