const CpuFeatures = struct {
    MAX_PAGE_SIZE : u8 = 0,
    EXECUTE_BIT : bool = false,
    READ_BIT : bool = false,
};

pub var FEATURES : CpuFeatures = CpuFeatures {};