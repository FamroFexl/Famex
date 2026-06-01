const std = @import("std");

pub const ArchData = struct {
    linker : std.Build.LazyPath,
    target : std.Build.ResolvedTarget,
    module : *std.Build.Module,
};

const Arch = enum {
    x86_64,
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    const options : std.Build.Module.CreateOptions = .{
        .red_zone = false,
        .pic = false,
        .optimize = optimize,
        .code_model = .kernel,
    };

    const arch_option = b.option(Arch, "arch", "Target architecture") orelse .x86_64;

    const arch : ArchData = switch(arch_option) {
        .x86_64 => module: {
            const x86 = @import("kernel/arch/x86_64/build.zig");
            break :module .{
                .linker = x86.get_linker(b),
                .target = x86.get_target(b),
                .module = x86.module(b, &options),
            };
        },
    };

    var options_copy : std.Build.Module.CreateOptions = options;
    options_copy.root_source_file = b.path("kernel/main.zig");
    options_copy.target = arch.target;

    const kernel = b.addExecutable(.{
        .name = "famex.elf",
        .root_module = b.createModule(options_copy),
        .use_lld = true,
        .use_llvm = true,
    });
    kernel.linkage = .static;
    kernel.entry = .disabled;
    kernel.setLinkerScript(arch.linker);
    kernel.root_module.addImport("Arch", arch.module);
    kernel.link_function_sections = true;
    kernel.link_data_sections = true;
    b.installArtifact(kernel);


}