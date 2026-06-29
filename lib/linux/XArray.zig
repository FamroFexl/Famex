const xarray = @cImport({@cInclude("xarray.h");});

val : xarray.struct_xarray,

pub const NodeSize = @sizeOf(xarray.struct_xa_node);