/// Zig-friendly wrapper around linux XArray implementation

const xarray = @cImport({@cInclude("xarray.h");});

val : xarray.struct_xarray,

pub fn setup() void {
    xarray.xarray_init();
}

pub const Node = struct {
    val : xarray.struct_xa_node,
};