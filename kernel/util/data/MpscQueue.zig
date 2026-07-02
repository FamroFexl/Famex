const std = @import("std");
const cpu = @import("arch").cpu;

pub const Node = struct {
    next : ?*@This(),
};

// Head and tail should not share a cacheline
head : *Node align(cpu.CACHELINE_SIZE),
tail : std.atomic.Value(*Node),
dummy : Node,

pub fn init(this : *@This()) void {
    this.dummy.next = null;
    this.head.next = &this.dummy;
    this.tail.store(&this.dummy, .unordered);
}

pub fn push(this : *@This(), node : *Node) void {
    node.next = null;

    const prev = this.tail.rmw(.Xchg, node, .release);

    prev.next = node;
}

pub fn pop(this : *@This()) ?*Node {
    const head = this.head;
    var next = head.next;

    if (next) |n| {
        this.head = n;
        return n;
    }

    if (head == this.tail.load(.acquire)) {
        return null;
    }

    while (true) {
        next = head.next;

        if (next == null) {
            cpu.spinWaitLoop();
            continue;
        }

        break;
    }

    this.head = next;
    return next;
}
