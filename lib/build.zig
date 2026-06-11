const std = @import("std");

const cwd = "lib/";

pub fn module(b : *std.Build, options : *const std.Build.Module.CreateOptions) *std.Build.Module {
    const lib_module = b.addModule("lib_module", options.*);
    lib_module.root_source_file = b.path(cwd ++ "root.zig");
    lib_module.addIncludePath(b.path(cwd ++ "include"));
    lib_module.addIncludePath(b.path(cwd ++ "acpica/include"));
    lib_module.addIncludePath(b.path(cwd ++ "linux/include"));

    return lib_module;
}