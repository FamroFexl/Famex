const arch = @import("arch");

pub fn validAccess(read : bool, write : bool, exec : bool) bool {
    _ = write;

    if (!read)
        return false;

    if (!exec and !arch.cpu.EXECUTE_PAGING_BIT)
        return false;

    return true;
}