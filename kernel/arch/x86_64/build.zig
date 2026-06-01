const std = @import("std");

pub fn module(b : *std.Build, options : *const std.Build.Module.CreateOptions) *std.Build.Module {
    var options_copy = options.*;
    options_copy.target = get_target(b);
    options_copy.root_source_file = b.path("kernel/arch/x86_64/init.zig");
    return b.createModule(options_copy);
}

pub fn get_linker(b : *std.Build) std.Build.LazyPath {
    return b.path("kernel/arch/x86_64/linker.ld");
}

pub fn get_target(b : *std.Build) std.Build.ResolvedTarget {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .ofmt = .elf,
        .abi = .none,
    });

    return target;
}