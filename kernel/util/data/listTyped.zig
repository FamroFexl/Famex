const std = @import("std");

pub fn ListTyped(comptime T : type, comptime linkField : []const u8) type {
    return struct {
        pub const Node = @This();

        prev : *Node,
        next : *Node,

        pub fn init(list : *@This()) void {
            list.prev = list;
            list.next = list;
        }

        pub fn empty(list : *@This()) bool {
            return list.next == list;
        }

        fn getLink(node : *T) *Node {
            return &@field(node, linkField);
        }

        fn getNode(link : *Node) *T {
            return @fieldParentPtr(linkField, link);
        }

        pub fn insertFront(list : *@This(), node : *T) void {
            const link = getLink(node);

            link.prev = list;
            link.next = list.next;
            list.next.prev = node;
            list.next = node;
        }

        pub fn insertBack(list : *@This(), node : *T) void {
            const link = getLink(node);

            link.next = list;
            link.prev = list.prev;
            list.prev.next = node;
            list.prev = node;
        }

        pub fn front(list : *@This()) ?*T {
            if (list.empty()) return null;
            return getNode(list.next);
        }

        pub fn back(list : *@This()) ?*T {
            if (list.empty()) return null;
            return getNode(list.prev);
        }

        pub fn remove(list : *@This(), node : *T) void {
            _ = list;

            const link = getLink(node);

            link.next.prev = link.prev;
            link.prev.next = link.next;

            link.prev = link;
            link.next = link;
        }

        pub fn removeFront(list : *@This()) ?*T {
            const next = getNode(list.next);
            if (list.empty()) return null;
            remove(list, next);

            return next;
        }

        pub fn removeBack(list : *@This()) ?*T {
            const prev = getNode(list.prev);
            if (list.empty()) return null;
            remove(list, prev);

            return prev;
        }

        pub const Iterator = struct {
            list : *Node,
            cur : *Node,

            pub fn next(this : *@This()) ?*T {
                if (this.cur.next == this.list)
                    return null;

                this.cur = this.cur.next;

                return getNode(this.cur);
            }

            pub fn prev(this : *@This()) ?*T {
                if (this.cur.prev == this.list)
                    return null;

                this.cur = this.cur.prev;
                return getNode(this.cur);
            }
        };

        pub fn iterator(this : *@This()) Iterator {
            return .{
                .list = this,
                .cur = this,
            };
        }

        pub fn contains(list : *@This(), node : *Node) bool {
            var next = list.next;
            while (next != list.prev) : (next = next.next) {
                if (next == node) return true;
            }

            return false;
        }

        pub fn indexOf(list : *@This(), node : *Node) ?usize {
            var next = list.next;
            var i = 0;
            while (next != list.prev) : (next = next.next) {
                if (next == node)
                    return i;
                i += 1;
            }

            return null;
        }

        pub fn at(list : *@This(), index : usize) ?*T {
            var next = list.next;
            var i = 0;
            while (next != list.prev) : (next = next.next) {
                if (i == index) return getNode(next);
                i += 1;
            }

            return null;
        }

        pub fn len(list : *@This()) usize {
            var next = list.next;
            var i = 0;
            while (next != list.prev) : (next = next.next) {
                i += 1;
            }

            return i;
        }

    };
}