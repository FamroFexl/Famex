const std = @import("std");

const cwd = "testProc/";

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget) !void {
    const testModule = b.addModule("testModule", .{
        .pic = false,
        .optimize = b.standardOptimizeOption(.{}),
        .target = target,
        .root_source_file = b.path(cwd ++ "main.zig"),
    });

    const testProc = b.addExecutable(.{
        .name = "testProc.elf",
        .root_module = testModule,
        .use_lld = true,
        .use_llvm = true,
        .linkage = .static,
    });

    b.installArtifact(testProc);
}