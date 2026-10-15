/// Zig-friendly wrapper around linux XArray implementation
const std = @import("std");

const xarray = @cImport({@cInclude("xarray.h");});

val : xarray.struct_xarray,

pub fn setup() void {
    xarray.xarray_init();
}

pub const Node = struct {
    val : xarray.struct_xa_node,
};

pub fn init(this : *@This(), allocate : bool) void {
    if (allocate) {
        xarray.xa_init_flags(&this.val, xarray.XA_FLAGS_ALLOC);
    }
    else {
        xarray.xa_init(&this.val);
    }
}

pub fn find(this : *@This(), index : u32) ?*anyopaque {
    var largeIndex : c_ulong = @intCast(index);
    return xarray.xa_find(&this.val, &largeIndex, @intCast(index), 0);
}

pub fn set(this : *@This(), index : u32, entry : *anyopaque) void {
    _ = xarray.xa_store(&this.val, @intCast(index), entry);
}

pub fn get(this : *@This(), index : u32) ?*anyopaque {
    return xarray.xa_load(&this.val, @intCast(index));
}

pub fn alloc(this : *@This(), min : u32, max : u32, entry : *anyopaque) u32 {
    var id : u32 = undefined;

    _ = xarray.xa_alloc(&this.val, &id, entry, .{
        .min = min,
        .max = max,
    });

    return id;
}

pub fn free(this : *@This(), index : u32) void {
    xarray.xa_release(&this.val, @intCast(index));
}