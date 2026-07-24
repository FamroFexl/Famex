const std = @import("std");

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

pub fn insertFront(list : *@This(), node : *Node) void {
    node.prev = list;
    node.next = list.next;
    list.next.prev = node;
    list.next = node;
}

pub fn insertBack(list : *@This(), node : *Node) void {
    node.next = list;
    node.prev = list.prev;
    list.prev.next = node;
    list.prev = node;
}

pub fn front(list : *@This()) ?*Node {
    if (list.empty()) return null;
    return list.next;
}

pub fn back(list : *@This()) ?*Node {
    if (list.empty()) return null;
    return list.prev;
}

pub fn remove(list : *@This(), node : *Node) void {
    _ = list;
    node.next.prev = node.prev;
    node.prev.next = node.next;
}

pub fn removeFront(list : *@This()) ?*Node {
    const next = list.next;
    if (list.empty()) return null;
    remove(list, list.next);

    return next;
}

pub fn removeBack(list : *@This()) ?*Node {
    const prev = list.prev;
    if (list.empty()) return null;
    remove(list, list.prev);

    return prev;
}

pub const Iterator = struct {
    list : *Node,
    cur : *Node,

    pub fn next(this : *@This()) ?*Node {
        if (this.cur.next == this.list)
            return null;

        this.cur = this.cur.next;
        return this.cur;
    }

    pub fn prev(this : *@This()) ?*Node {
        if (this.cur.prev == this.list)
            return null;

        this.cur = this.cur.prev;
        return this.cur;
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

pub fn at(list : *@This(), index : usize) ?*Node {
    var next = list.next;
    var i = 0;
    while (next != list.prev) : (next = next.next) {
        if (i == index) return next;
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