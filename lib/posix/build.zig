const std = @import("std");

const cwd = "lib/posix/";

pub fn module(b : *std.Build, options : *const std.Build.Module.CreateOptions) *std.Build.Module {
    const posixModule = b.createModule(options.*);
    posixModule.root_source_file = b.path(cwd ++ "root.zig");

    posixModule.addIncludePath(b.path(cwd ++ "include/"));

    return posixModule;
}