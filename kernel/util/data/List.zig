const std = @import("std");

pub const Node = @This();

const ListError = error {
    NodeNotInList,
    IndexDoesNotExist
};

prev : *Node,
next : *Node,

pub fn init(list : *@This()) void {
    list.prev = list;
    list.next = list;
}

pub fn empty(list : *@This()) bool {
    return list.next == list;
}

pub fn insert_front(list : *@This(), node : *Node) void {
    node.prev = list;
    node.next = list.next;
    list.next.prev = node;
    list.next = node;
}

pub fn insert_back(list : *@This(), node : *Node) void {
    node.next = list;
    node.prev = list.prev;
    list.prev.next = node;
    list.prev = node;
}

pub fn front(list : *@This()) *Node {
    return list.next;
}

pub fn back(list : *@This()) *Node {
    return list.prev;
}

pub fn remove(list : *@This(), node : *Node) void {
    _ = list;
    node.next.prev = node.prev;
    node.prev.next = node.next;
}

pub fn remove_front(list : *@This()) *Node {
    const next = list.next;
    remove(list.next);

    return next;
}

pub fn remove_back(list : *@This()) *Node {
    const prev = list.prev;
    remove(list.prev);

    return prev;
}

pub fn contains(list : *@This(), node : *Node) bool {
    var next = list.next;
    while (next != list.prev) : (next = next.next) {
        if (next == node) return true;
    }

    return false;
}

pub fn index_of(list : *@This(), node : *Node) !usize {
    var next = list.next;
    var i = 0;
    while (next != list.prev) : (next = next.next) {
        if (next == node)
            return i;
        i += 1;
    }

    return ListError.NodeNotInList;
}

pub fn at(list : *@This(), index : usize) !*Node {
    var next = list.next;
    var i = 0;
    while (next != list.prev) : (next = next.next) {
        if (i == index) return next;
        i += 1;
    }

    return ListError.IndexDoesNotExist;
}

pub fn size(list : *@This()) usize {
    var next = list.next;
    var i = 0;
    while (next != list.prev) : (next = next.next) {
        i += 1;
    }

    return i;
}