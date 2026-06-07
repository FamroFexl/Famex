const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    var options : std.Build.Module.CreateOptions = .{
        .red_zone = false,
        .pic = false,
        .optimize = optimize,
        .code_model = .kernel,
    };

    var linker : std.Build.LazyPath = undefined;

    const arch = @import("arch/build.zig");
    const arch_data : arch.ArchData = arch.module(b, &options, &linker);
    const arch_module = arch_data.module;
    const arch_api_module = arch_data.api_module;

    const kernel_module = @import("kernel/build.zig").module(b, &options);

    const lib_module =@import("lib/build.zig").module(b, &options);

    arch_module.addImport("lib", lib_module);
    arch_module.addImport("kernel", kernel_module);
    arch_module.addImport("arch", arch_module);
    arch_module.addImport("arch_api", arch_api_module);

    arch_api_module.addImport("arch", arch_module);
    arch_api_module.addImport("kernel", kernel_module);

    kernel_module.addImport("kernel", kernel_module);
    kernel_module.addImport("arch", arch_api_module);
    kernel_module.addImport("lib", lib_module);

    lib_module.addImport("arch", arch_api_module);

    const famex = b.addExecutable(.{
        .name = "famex.elf",
        .root_module = arch_module,
        .use_lld = true,
        .use_llvm = true,
    });

    famex.setLinkerScript(linker);
    famex.linkage = .static;
    famex.entry = .disabled;
    famex.link_function_sections = true;
    famex.link_data_sections = true;

    b.installArtifact(famex);
}