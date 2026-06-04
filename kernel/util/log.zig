const std = @import("std");
const types = @import("kernel").util.types;

pub fn outb(port: u16, value: u8) void {
    asm volatile (
        "outb %[val], %[port]"
        :
        : [val] "{al}" (value),
          [port] "{dx}" (port),
    );
}

const COM1 = 0x3F8;

pub fn print_chars(str : [*]const u8, num : u64) void {
    for(0..num) |i| {
        outb(COM1, str[i]);
    }
}

pub fn print_size(num : u64, min_align : u6) void {
    const prefixes = [_][]const u8 {"KiB", "MiB", "GiB", "TiB", "PiB", "EiB"};
    var buf : [64]u8 = undefined;

    var cpy: f64 = @floatFromInt(num);
    cpy /= 1024;
    var cur_prefix : u8 = 0;
    while (cpy / 1024 >= 1) {
        cpy /= 1024;
        cur_prefix += 1;
    }

    const out = std.fmt.bufPrint(&buf, "{d:.1}{s}", .{cpy, prefixes[cur_prefix]}) catch {
        print_chars("bufPrint err", 12);
        return;
    };

    const out_align = if(min_align < out.len) out.len else min_align;

    @memset(buf[out.len..out_align], ' ');
    print_chars(out.ptr, if(out.len > out_align) out.len else out_align);
}

pub fn print(comptime str : []const u8, args: anytype) void {
    var buf : [1000]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, str, args) catch {
        print_chars("bufPrint err", 12);
        return;
    };
    print_chars(out.ptr, out.len);
}

pub fn print_char(char : u8, num : u8) void {
    var buf : [128]u8 = undefined;
    @memset(&buf, char);

    print_chars(&buf, num);
}

pub fn panic(comptime str : []const u8, args: anytype) void {
    print(str, args);
    //unreachable;
}

// Kernel Panic if expr true
pub fn apanic(expr : bool, comptime str : []const u8, args: anytype) void {
    if (!expr) return;

    print(str, args);
    //unreachable;
}