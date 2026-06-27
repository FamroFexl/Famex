const kernel = @import("kernel");
const bin = kernel.util.binary;
const log = kernel.util.log;
const mem = kernel.mm.memory;

const std = @import("std");

num_bits : usize,
addr : [*]u64,

/// Init a bitmap with an amount of bits
pub fn init(bmap : *@This(), addr : *anyopaque, num_bits : u64) void {
    bmap.num_bits = num_bits;
    bmap.addr = bin.castPtr([*]u64, addr);
}

/// Create a bitmap with an amount of bits
pub fn create(addr : *anyopaque, num_bits : u64) @This() {
    return .{
        .addr = bin.castPtr([*]u64, addr),
        .num_bits = num_bits,
    };
}

pub fn clear(bmap : *@This(), index : anytype, num : anytype) void {
    std.debug.assert(index + num < bmap.num_bits);

    const start_word : u64 = index / 64;
    const start_word_index : u6 = index % 64;
    const end_word : u64 = (index + num) / 64;
    const end_word_index : u6 = (index + num) % 64;

    mem.memset(&bmap.addr[start_word + 1], ((start_word + 1) - (end_word - 1)) * 8, 0);

    (&bmap.addr[start_word]).* &= bin.setBits(start_word_index);
    (&bmap.addr[end_word]).* &= ~bin.setBits(end_word_index);
}

pub fn set(bmap : *@This(), index : anytype, num : anytype) void {
    std.debug.assert(index + num < bmap.num_bits);

    const start_word : u64 = index / 64;
    const start_word_index : u6 = @intCast(index % 64);
    const end_word : u64 = (index + num) / 64;
    const end_word_index : u6 = @intCast((index + num) % 64);

    if (end_word - start_word > 1)
        mem.memset(&bmap.addr[start_word + 1], ((start_word + 1) - (end_word - 1)) * 8, std.math.maxInt(u8));

    (&bmap.addr[start_word]).* &= ~bin.setBits(start_word_index);
    (&bmap.addr[end_word]).* &= bin.setBit(end_word_index);
}

pub fn get(bmap : *@This(), index : anytype) bool {
    std.debug.assert(index < bmap.num_bits);

    const word : u64 = index / 64;
    const word_idx : u6 = @intCast(index % 64);

    return bmap.addr[word].* & bin.setBit(word_idx);
}

/// Find a number of clear bits
pub fn findClear(bmap : *@This(), num : anytype) ?u64 {
    std.debug.assert(num > 0 and num < bmap.num_bits);
    var remaining = num;
    var out_idx : ?u64 = null;

    const max = std.math.divCeil(usize, bmap.num_bits, 64) catch unreachable;
    for (0..max) |i| {
        const word = (&bmap.addr[i]).* | if (i == max - 1) ~(bin.setBits(bmap.num_bits % 64)) else 0;

        // Check for an ongoing span if the value spans multiple words
        if (out_idx != null) {
            const start = @ctz(word);
            if (start >= remaining)
                return out_idx;
            if (start == 64) {
                remaining -= 64;
                continue;
            }
            out_idx = null;
            remaining = num;
        }

        // Find valid contenders for number of bits
        const inv = ~word;
        var cur : u64 = inv;
        for (1..bin.min(num + 1, 64)) |j| {
            cur &= inv << @intCast(j);
            if (cur == 0) break;
        }

        if (cur > 0) {
            return i * 64 + @ctz(cur) - num;
        }

        const zeros = @clz(word);
        if (zeros > 0) {
            out_idx = i * 64 + 64 - zeros;
        }
    }

    return null;
}

/// Find and set a number of clear bits
pub fn findAndSet(bmap : *@This(), num : anytype) ?u64 {
    const index = findClear(bmap, num) orelse return null;
    set(bmap, index, num);
    return index;
}