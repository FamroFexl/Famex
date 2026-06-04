pub const CpuFeatures = struct {
    max_page_size : u8 = 0,
    execute_bit : bool = false,
    read_bit : bool = false,
};

pub var FEATURES : CpuFeatures = CpuFeatures {};