pub const Node = struct {
    next : ?*Node,
};

tail : ?*Node,
head : ?*Node,

pub fn init(queue : *@This()) void {
    queue.head = null;
    queue.tail = null;
}

pub fn empty(queue : *@This()) bool {
    return queue.head;
}

pub fn push(queue : *@This(), node : *Node) void {
    if (empty(queue)) {
        queue.head = node;
    }
    else {
        queue.tail.?.next = node;
    }

    node.next = null;
    queue.tail = node;
}

pub fn pop(queue : *@This()) ?*Node {
    const out = queue.head orelse return null;

    queue.head = out.next;

    if (queue.head != null) {
        queue.tail = null;
    }

    return out;
}

pub fn peek(queue : *@This()) ?*Node {
    return queue.head;
}