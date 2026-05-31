const std = @import("std");

pub const Arch = struct {
    linker : std.Build.LazyPath,
    module : std.Build.Module,
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    var options : std.Build.Module.CreateOptions = .{
        .red_zone = false,
        .pic = false,
        .optimize = optimize,
        .code_model = .kernel,
    };

    const arch_target = b.standardTargetOptions(.{});
    var arch : Arch = switch(arch_target.result.cpu.arch) {
        .x86_64 => module: {
            const x86 = @import("kernel/arch/x86_64/build.zig");
            break :module .{
                .linker = x86.get_linker(b),
                .module = x86.module(b, &options),
            };
        },
        else => @panic("Architecture not supported!\n")
    };

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("kernel/main.zig"),
            .target = options,
            .optimize = optimize,
            .code_model = .kernel,
        }),
    });
    kernel.setLinkerScript(arch.linker);
    kernel.link_function_sections = true;
    kernel.link_data_sections = true;
    b.installArtifact(kernel);


}