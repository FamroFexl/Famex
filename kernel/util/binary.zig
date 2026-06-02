pub fn set_bit(bit : u6) u64 {
    return @as(u64, 1) << bit;
}

pub fn set_bits(bit : u6) u64 {
    return set_bit(bit) - 1;
}

pub fn align_up(num : u64, mul : u64) u64 {
    return (num + mul - 1) & ~(mul - 1);
}

pub fn align_down(num : u64, mul : u64) u64 {
    return num & ~(mul - 1);
}