pub fn set_bit(bit : anytype) u64 {
    return @as(u64, 1) << @intCast(bit);
}

pub fn get_bit(bit : anytype, bits : anytype) bool {
    return (bits >> bit) & 1 == 1;
}

pub fn get_bits(amount : anytype, index : anytype, bits : anytype) u64 {
    return (@as(u64, @intCast(bits)) >> @intCast(index)) & set_bits(amount);
}

pub fn set_bits(bit : anytype) u64 {
    return set_bit(bit) - 1;
}

pub fn get_align(num : u64) u64 {
    return num & (~num + 1);
}

pub fn align_up(num : anytype, mul : anytype) u64 {
    const num_typed : u64 = @intCast(num);
    const mul_typed : u64 = @intCast(mul);
    return (num_typed + mul_typed - 1) & ~(mul_typed - 1);
}

pub fn align_down(num : anytype, mul : anytype) u64 {
    const num_typed : u64 = @intCast(num);
    const mul_typed : u64 = @intCast(mul);
    return num_typed & ~(mul_typed - 1);
}

pub fn max_align_between(addr : anytype, limit : anytype) u64 {
    const range : u64 = dist(addr, limit);
    const pow2 : u64 = set_bit(63 - @clz(range));
    return min(pow2, get_align(addr));
}

pub fn round_up_pow2(val : anytype) u64 {
    if (val <= 1) return 1;

    return set_bit(64 - @clz(val - 1));
}

pub fn set_flag(flag : anytype, bin : *u64) void {
    bin.* |= set_bit(@as(u6, @intCast(flag)));
}

pub fn clear_flag(flag : anytype, bin : *u64) void {
    bin.* &= ~set_bit(@as(u6, @intCast(flag)));
}

pub fn get_flag(flag : anytype, bin : u64) bool {
    return bin >> @as(u6, @intCast(flag)) & 1 == 1;
}

pub fn change_flag(flag : anytype, bin : *u64, set : bool) void {
    bin.* = (bin.* & ~(1 << flag)) | (set << flag);
}

pub fn min(num1 : anytype, num2: anytype) u64 {
    return if (num1 > num2) num2 else num1;
}

pub fn max(num1 : anytype, num2: anytype) u64 {
    return if (num1 > num2) num1 else num2;
}

pub fn dist(num1 : anytype, num2 : anytype) u64 {
    return if(num1 > num2) num1 - num2 else num2 - num1;
}

pub fn set_if_larger(comptime T: type, current: *T, new_value: T) void {
    if (new_value > current.*) {
        current.* = new_value;
    }
}

pub fn set_if_smaller(comptime T: type, current: *T, new_value: T) void {
    if (new_value < current.*) {
        current.* = new_value;
    }
}