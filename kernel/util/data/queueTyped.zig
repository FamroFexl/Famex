pub fn QueueTyped(comptime T : type, comptime linkField : []const u8) type {
    return struct {
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
            return queue.head == null;
        }

        fn getLink(node : *T) *Node {
            return &@field(node, linkField);
        }

        fn getNode(link : *Node) *T {
            return @fieldParentPtr(linkField, link);
        }

        pub fn push(queue : *@This(), node : *T) void {
            const link = getLink(node);

            if (empty(queue)) {
                queue.head = link;
            }
            else {
                queue.tail.?.next = link;
            }

            link.next = null;
            queue.tail = link;
        }

        pub fn pop(queue : *@This()) ?*T {
            const out = queue.head orelse return null;

            queue.head = out.next;

            if (queue.head != null) {
                queue.tail = null;
            }

            return getNode(out);
        }

        pub fn peek(queue : *@This()) ?*T {
            return getNode(queue.head);
        }
    };
}