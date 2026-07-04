/// Zig-friendly wrapper around linux MapleTree implementation

const std = @import("std");

const maple = @cImport({@cInclude("maple_tree.h");});

val : maple.struct_maple_tree,

const MapleTree = @This();

/// Setup MapleTree structures
pub const setup = maple.maple_tree_init;

const Flags = packed struct(u32) {
    allocRange : bool = false,
    useRcu : bool = false,
    height : u5 = 0,
    __pad1 : u4 = 0,
    allocWrapped : bool = false,
    __pad2 : u20 = 0,
};

pub fn init(tree : *@This(), flags : Flags) void {
    maple.mt_init_flags(&tree.val, @bitCast(flags));
}

/// Lock the tree
pub fn lock(tree : *@This()) void {
    maple.mtree_lock(tree);
}

/// Unlock the tree
pub fn unlock(tree : *@This()) void {
    maple.mtree_unlock(tree);
}

pub fn inRcu(tree : *@This()) void {
    return maple.mt_in_rcu(&tree.val);
}

pub fn enableRcu(tree : *@This()) void {
    maple.mt_set_in_rcu(&tree.val);
}

pub fn disableRcu(tree : *@This()) void {
    maple.mt_clear_in_rcu(&tree.val);
}

/// Delete the tree
pub fn delete(tree : *@This()) void {
    maple.mtree_destroy(&tree.val);
}

/// Duplicate the tree into new
pub fn dup(tree : *@This(), new : *@This()) void {
    maple.mtree_dup(&tree.val, &new.val);
}

/// Is the tree empty
pub fn empty(tree : *@This()) bool {
    return maple.mtree_empty(&tree.val) == 0;
}

/// Erase the node at addr
pub fn erase(tree : *@This(), addr : u64) void {
    maple.mtree_erase(&tree.val, addr);
}

/// Load the entry at addr
pub fn load(tree : *@This(), addr : u64) ?*anyopaque {
    return maple.mtree_load(&tree.val, addr);
}

pub fn insert(tree : *@This(), addr : u64, data : ?*anyopaque) void {
    maple.mtree_insert(&tree.val, addr, data);
}

pub fn insertRange(tree : *@This(), first : u64, last : u64, data : ?*anyopaque) void {
    maple.mtree_insert_range(&tree.val, first, last, data);
}

pub fn store(tree : *@This(), addr : u64, data : ?*anyopaque) void {
    maple.mtree_store(&tree.val, addr, data);
}

pub fn storeRange(tree : *@This(), first : u64, last : u64, data : ?*anyopaque) void {
    maple.mtree_store_range(&tree.val, first, last, data);
}

pub fn find(tree : *@This(), index : *u64, max : u64) ?*anyopaque {
    return maple.mt_find(&tree.val, index, max);
}

pub fn findAfter(tree : *@This(), index : *u64, max : u64) ?*anyopaque {
    return maple.mt_find_after(&tree.val, index, max);
}

pub fn next(tree : *@This(), index : u64, max : u64) ?*anyopaque {
    return maple.mt_next(&tree.val, index, max);
}

pub fn prev(tree : *@This(), index : u64, min : u64) ?*anyopaque {
    return maple.mt_prev(&tree.val, index, min);
}

pub const MaState = struct {
    val : maple.struct_ma_state,

    pub fn create(tree : *MapleTree, first : u64, end : u64) MaState {
        return .{.val = .{
            .tree = tree.val,
            .index = first,
            .last = end,
            .node = null,
            .status = maple.ma_start,
            .min = 0,
            .max = std.math.maxInt(c_ulong),
            .alloc = null,
            .mas_flags = 0,
        }};
    }

    pub fn init(state : *@This(), tree : *MapleTree, addr : u64) void {
        state = std.mem.zeroes(maple.struct_ma_state);
        state = .{.val = .{
            .tree = tree,
            .index = addr,
            .last = addr,
            .max = std.math.maxInt(c_ulong),
            .status = maple.ma_start,
            .node = null,
        }};
    }
};