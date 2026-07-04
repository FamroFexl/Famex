/// Zig-friendly wrapper around linux RBTree implementation

const rb = @cImport({@cInclude("rbtree.h");});

const rbtree = @This();

/// Type the RBNode is in
pub fn RBTree(comptime T : type, comptime nodeField : []const u8, comptime cmpField : []const u8, comptime cached : bool) type {
    const rootData = if (cached) rb.struct_rb_root_cached else rb.struct_rb_root;

    return struct {
        root : rootData,

        pub const Node = struct {
            node : rb.struct_rb_node = .{
                .__rb_parent_color = 0,
                .rb_left = null,
                .rb_right = null,
            },

            pub fn next(this : *@This()) *@This() {
                return @fieldParentPtr("node", rb.rb_next(&this.node));
            }

            pub fn prev(this : *@This()) *@This() {
                return @fieldParentPtr("node", rb.rb_prev(&this.node));
            }

            /// Returns the holding type of the node
            pub fn holder(this : *@This()) *T {
                return @fieldParentPtr(nodeField, this);
            }

            /// Clear the node
            pub fn clear(this : *@This()) void {
                this.node.__rb_parent_color = 0;
            }

            /// Is the node empty
            pub fn empty(this : *@This()) bool {
                return this.node.__rb_parent_color == 0;
            }
        };

        fn compare(keyPtr : ?*const anyopaque, node : ?*const rb.struct_rb_node) callconv(.c) c_int {
            const key : *u64 = @ptrCast(@alignCast(keyPtr));
            const exp1 : T = @fieldParentPtr(nodeField, node.?);

            const val = &@field(exp1, cmpField);

            return if (key.* < val.*) -1 else if (key.* > val.*) 1 else 0;
        }

        fn less(node : ?*rb.struct_rb_node, node2 : ?*const rb.struct_rb_node) callconv(.c) bool {
            const exp1 : T = @fieldParentPtr(nodeField, node.?);
            const exp2 : T = @fieldParentPtr(nodeField, node2.?);

            return @field(exp1, cmpField) < @field(exp2, cmpField);
        }

        pub fn init(this : *@This()) void {
            if (cached) rb.rb_cached_init(&this.root) else rb.rb_init(&this.root);
        }

        pub fn empty(this : *@This()) bool {
            const tree : rb.struct_rb_root = if (cached) &this.root.rb_root else &this.root;
            return tree.rb_node == null;
        }

        pub fn first(this : *@This()) ?*Node {
            const node : ?*rb.struct_rb_node = if (cached) rb.rb_first_cached(&this.root.rb_leftmost) else rb.rb_first(&this.root);
            if (node) |n| {
                return .{.node = n};
            }
            return null;
        }

        pub fn last(this : *@This()) ?*Node {
            const node : ?*rb.struct_rb_node = if (cached) rb.rb_last(&this.root.rb_root) else rb.rb_last(&this.root);
            if (node) |n| {
                return .{.node = n};
            }
            return null;
        }

        pub fn erase(this : *@This(), node : *Node) void {
            if (cached) rb.rb_erase_cached(&node.node, &this.root) else rb.rb_erase(&node.node, &this.root);
        }

        pub fn replace(this : *@This(), old : *Node, new : *Node) void {
            if (cached) {
                rb.rb_replace_node_cached(&old.node, &new.node, &this.root);
            }
            else {
                rb.rb_replace_node(&old.node, &new.node, &this.root);
            }
        }

        pub fn add(this : *@This(), node : *Node) void {
            if (cached) {
                rb.rb_add_cached(&node.node, &this.root, less);
            }
            else {
                rb.rb_add(&node.node, &this.root, less);
            }
        }

        pub fn findAdd(this : *@This(), node : *Node) ?*Node {
            const out = rb.rb_find_add(&node.node, if (cached) &this.root.rb_root else &this.root, compare);

            if (out) |o| {
                return .{.node = @ptrCast(o)};
            }

            return null;
        }

        pub fn find(this : *@This(), key : anytype) ?*Node {
            const stat : u64 = key;
            const out = rb.rb_find(@ptrCast(@alignCast(&stat)), if (cached) &this.root.rb_root else &this.root, compare);

            if (out) |o| {
                return .{.node = @ptrCast(o)};
            }

            return null;
        }

        pub fn findFirst(this : *@This(), key : anytype) ?*Node {
            const stat : u64 = key;
            const out = rb.rb_find_first(@ptrCast(@alignCast(&stat)), if (cached) &this.root.rb_root else &this.root, compare);

            if (out) |o| {
                return .{.node = @ptrCast(o)};
            }

            return null;
        }

        pub fn findAfter(this : *@This(), key : anytype) ?*Node {
            const stat : u64 = key;
            const out = rb.rb_find_after(@ptrCast(@alignCast(&stat)), if (cached) &this.root.rb_root else &this.root, compare);

            if (out) |o| {
                return .{.node = @ptrCast(o)};
            }

            return null;
        }

        pub fn nextMatch(this : *@This(), node : *Node, key : anytype) ?*Node {
            _ = this;
            const stat : u64 = key;
            const out = rb.rb_next_match(@ptrCast(@alignCast(&stat)), &node.node, compare);

            if (out) |o| {
                return .{.node = @ptrCast(o)};
            }

            return null;
        }
    };
}