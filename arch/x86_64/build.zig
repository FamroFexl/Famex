const std = @import("std");

const arch = @import("../build.zig");

const cwd = "arch/x86_64/";

pub fn module(b : *std.Build, options : *std.Build.Module.CreateOptions, linker : *std.Build.LazyPath) arch.ArchData {
    const x86 = std.Target.x86;
    options.target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .ofmt = .elf,
        .abi = .none,
        .cpu_features_add = x86.featureSet(&.{.soft_float}),
        .cpu_features_sub = x86.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });

    linker.* = b.path(cwd ++ "linker.ld");

    var arch_data : arch.ArchData = undefined;

    const x86_module = b.createModule(options.*);
    x86_module.root_source_file = b.path(cwd ++ "root.zig");
    arch_data.module = x86_module;

    const x86_export_module = b.createModule(options.*);
    x86_export_module.root_source_file = b.path(cwd ++ "export/root.zig");
    arch_data.export_module = x86_export_module;

    return arch_data;
}