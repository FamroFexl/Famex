const std = @import("std");

const arch = @import("../build.zig");

const gen_offsets = @import("scripts/gen_offsets/build.zig");
const gen_irq_entries = @import("scripts/gen_irq_entries/build.zig");

const cwd = "arch/x86_64/";

pub fn module(b : *std.Build, options : *std.Build.Module.CreateOptions) arch.ArchData {
    return .{
        .arch_module = arch_module(b, options),
        .api_module = api_module(b, options),
        .linker_script = get_linker(b),
        .target = get_target(b),
    };
}

fn get_linker(b : *std.Build) std.Build.LazyPath {
    return b.path(cwd ++ "linker.ld");
}

fn get_target(b : *std.Build) std.Build.ResolvedTarget {
    const x86 = std.Target.x86;

    return b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .ofmt = .elf,
        .abi = .none,
        .cpu_features_add = x86.featureSet(&.{.soft_float}),
        .cpu_features_sub = x86.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });
}

fn arch_module(b : *std.Build, options : *std.Build.Module.CreateOptions) *std.Build.Module {
    const x86_module = b.addModule("arch_module",options.*);
    x86_module.root_source_file = b.path(cwd ++ "root.zig");
    x86_module.resolved_target = get_target(b);

    const gen_offsets_file = gen_offsets.exec(b, b.path(cwd ++ "registers.zig"), b.path("kernel/io/asmLayout.zig"),"asm_offsets.h");
    x86_module.addIncludePath(gen_offsets_file.dirname());

    x86_module.addAssemblyFile(b.path(cwd ++ "registers.S"));
    x86_module.addAssemblyFile(b.path(cwd ++ "entry.S"));

    const gen_irq_entries_file = gen_irq_entries.exec(b, "irq_entries.s");
    x86_module.addAssemblyFile(gen_irq_entries_file);

    return x86_module;
}

fn api_module(b : *std.Build, options : *std.Build.Module.CreateOptions) *std.Build.Module {
    const x86_api_module = b.addModule("arch_api_module", options.*);
    x86_api_module.root_source_file = b.path(cwd ++ "api/root.zig");
    x86_api_module.resolved_target = get_target(b);

    return x86_api_module;
}