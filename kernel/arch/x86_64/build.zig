const std = @import("std");

pub fn module(b : *std.Build, options : *std.Build.Module.CreateOptions) *std.Build.Module {
    var x86_options = options.*;
    x86_options.target = get_target();
    x86_options.root_source_file = b.path("init.zig");

    return b.createModule(x86_options);
}

pub fn get_linker(b : *std.Build) std.Build.LazyPath {
    return b.path("linker.ld");
}

pub fn get_target() std.Build.ResolvedTarget {
    const Target = std.Target.x86;

    const arch_query : std.Build.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .ofmt = .elf,
        .cpu_features_add = Target.featureSet(&.{.soft_float}),
        .cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx}),
    };

    return arch_query;
}

pub fn get_arch() main.Arch {
    const arch = main.Arch {
        .get_linker = &get_linker,
        .get_target = &get_target,
    };

    return arch;
}