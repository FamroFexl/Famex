const std = @import("std");

const cwd = "kernel/";

pub fn module(b : *std.Build, options : *std.Build.Module.CreateOptions) *std.Build.Module {
    var kernel_module = b.createModule(options.*);
    kernel_module.root_source_file = b.path(cwd ++ "root.zig");

    return kernel_module;
}