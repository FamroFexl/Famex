const std = @import("std");

const cwd = "lib/acpica/";

fn collectFiles(b : *std.Build, comptime rel_path : []const u8, extension : []const u8) ![]const []const u8 {
    const abs = b.path(cwd ++ rel_path).getPath(b);
    const dir = try std.Io.Dir.openDirAbsolute(b.graph.io, abs, .{.iterate = true,});
    var walker = try std.Io.Dir.walk(dir, b.allocator);

    var list = try std.ArrayList([]const u8).initCapacity(b.allocator, 30);

    while (true) {
        const entry = (walker.next(b.graph.io) catch break) orelse break;
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, extension)) continue;
        const owned = try b.allocator.dupe(u8, entry.path);
        try list.append(b.allocator, owned);
    }
    
    return try list.toOwnedSlice(b.allocator);
}

pub fn module(b : *std.Build, options : *const std.Build.Module.CreateOptions) *std.Build.Module {
    const acpica_module = b.addTranslateC(.{
        .root_source_file = b.path("lib/acpica/include/acpi.h"),
        .target = options.target.?,
        .optimize = options.optimize.?,
        .link_libc = false,
    }).addModule("acpica");

    const files = collectFiles(b, "src", ".c") catch undefined;

    acpica_module.addCSourceFiles(.{
        .root = b.path(cwd ++ "src/"),
        .files = files,
    });

    acpica_module.addIncludePath(b.path(cwd ++ "include"));

    return acpica_module;
}