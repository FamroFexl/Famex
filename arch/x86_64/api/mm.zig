const cpu = @import("cpu.zig");

pub fn validAccess(read : bool, write : bool, exec : bool) bool {
    _ = write;

    if (!read)
        return false;

    if (!exec and !cpu.FEATURES.EXECUTE_BIT)
        return false;

    return true;
}