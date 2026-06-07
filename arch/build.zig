const std = @import("std");

const cwd = "arch/";

const Arch = enum {
    x86_64,
};

pub const ArchData = struct {
    module : *std.Build.Module,
    api_module : *std.Build.Module,
};

pub fn module(b : *std.Build, options : *std.Build.Module.CreateOptions, linker : *std.Build.LazyPath) ArchData {
    const arch_option = b.option(Arch, "arch", "Target architecture") orelse .x86_64;

    var arch_data : ArchData = undefined;

    switch(arch_option) {
        .x86_64 => {
            arch_data = @import("x86_64/build.zig").module(b, options, linker);
        }
    }

    return arch_data;
}