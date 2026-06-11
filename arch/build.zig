const std = @import("std");

const cwd = "arch/";

const Arch = enum {
    x86_64,
};

pub const ArchData = struct {
    arch_module : *std.Build.Module,
    api_module : *std.Build.Module,
    linker_script : std.Build.LazyPath,
    target : std.Build.ResolvedTarget,
};

pub fn module(b : *std.Build, options : *std.Build.Module.CreateOptions) ArchData {
    const arch_option = b.option(Arch, "arch", "Target architecture") orelse .x86_64;

    return switch(arch_option) {
        .x86_64 => @import("x86_64/build.zig").module(b, options),
    };
}