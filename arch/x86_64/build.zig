const std = @import("std");

const arch = @import("../build.zig");

const gen_offsets = @import("scripts/gen_offsets/build.zig");
const gen_irq_entries = @import("scripts/gen_irq_entries/build.zig");

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

    const gen_offsets_file = gen_offsets.exec(b, b.path(cwd ++ "registers.zig"),"asm_offsets.h");
    x86_module.addIncludePath(gen_offsets_file.dirname());

    x86_module.addAssemblyFile(b.path(cwd ++ "registers.S"));
    x86_module.addAssemblyFile(b.path(cwd ++ "entry.S"));

    const gen_irq_entries_file = gen_irq_entries.exec(b, "irq_entries.s");
    x86_module.addAssemblyFile(gen_irq_entries_file);

    const x86_api_module = b.createModule(options.*);
    x86_api_module.root_source_file = b.path(cwd ++ "api/root.zig");
    arch_data.api_module = x86_api_module;

    return arch_data;
}