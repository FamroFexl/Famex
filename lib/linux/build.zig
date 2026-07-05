const std = @import("std");

const cwd = "lib/linux/";

pub fn module(b : *std.Build, options : *const std.Build.Module.CreateOptions) *std.Build.Module {
    const linuxModule = b.createModule(options.*);
    linuxModule.root_source_file = b.path(cwd ++ "root.zig");

    linuxModule.addCSourceFiles(.{
        .root = b.path(cwd ++ "src/"),
        .files = &.{
            "maple_tree.c",
            "rbtree.c",
            "xarray.c",
        },
    });

    linuxModule.addIncludePath(b.path(cwd ++ "include/"));

    return linuxModule;
}
