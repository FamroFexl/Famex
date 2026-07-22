pub const errno = @cImport({@cInclude("errno.h");});
//pub const times = @cImport({@cInclude("times.h");});
pub const times = @import("times.zig");
pub const types = @import("types.zig");