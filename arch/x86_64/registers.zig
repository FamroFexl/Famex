pub extern fn get_cr3() callconv(.c) u64;

pub extern fn set_cr3(cr3 : u64) callconv(.c) void;
