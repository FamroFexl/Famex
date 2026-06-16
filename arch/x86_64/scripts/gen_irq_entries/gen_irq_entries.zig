const std = @import("std");

var writer : std.Io.File.Writer = undefined;

fn gen_pair(comptime str : []const u8, num : anytype) void {
    writer.interface.print(str, .{num}) catch return;
}

fn gen_string(comptime str : []const u8) void {
    writer.interface.print(str, .{}) catch return;
}

pub fn main(init: std.process.Init) !void {
    var buf : [100000]u8 = undefined;
    writer = std.Io.File.stdout().writerStreaming(init.io, &buf);

    gen_string("# This file is auto-generated. Do not edit manually.\n\n");
    gen_string("# Generic irq entry points for the IDT that resolve to a single entry\n\n");

    gen_string(".code64\n.intel_syntax noprefix\n\n.section .entry.text, \"ax\"\n");
    gen_string("\n.extern irqEntry\n\n");

    gen_string(".global irqStubTable\nirqStubTable:\n");
    for (0..256) |i| {
        gen_pair("\t.quad irq_{}\n", i);
    }

    gen_string("\n");
    for (0..256) |i| {
        gen_pair("irq_{}:\n", i);
        gen_pair("\tpush {}\n", i);
        gen_string("\tjmp irqEntry\n");
    }

    try writer.interface.flush();
}