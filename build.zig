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

    const arch_data = @import("arch/build.zig").module(b, &options);
    const arch_module = arch_data.arch_module;
    const arch_api_module = arch_data.api_module;
    options.target = arch_data.target;

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

    famex.setLinkerScript(arch_data.linker_script);
    famex.linkage = .static;
    famex.entry = .disabled;
    famex.link_function_sections = true;
    famex.link_data_sections = true;

    b.installArtifact(famex);

    const famex_check = b.addExecutable(.{
        .name = "famex.elf",
        .root_module = arch_module,
        .use_lld = true,
        .use_llvm = true,
    });

    const check = b.step("check", "Check if famex compiles");
    check.dependOn(&famex_check.step);
}