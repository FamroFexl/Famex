const std = @import("std");

const cwd = "testProc/";

const posix = @import("posix");

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, modules : *std.StringHashMap(*std.Build.Module)) !void {
    const testModule = b.addModule("testModule", .{
        .pic = false,
        .optimize = b.standardOptimizeOption(.{}),
        .target = target,
        .root_source_file = b.path(cwd ++ "main.zig"),
        .red_zone = false,
    });

    testModule.addImport("posix", modules.get("posix").?);

    testModule.addAssemblyFile(b.path(cwd ++ "asm.s"));

    const testProc = b.addExecutable(.{
        .name = "testProc.elf",
        .root_module = testModule,
        .use_lld = true,
        .use_llvm = true,
        .linkage = .static,
    });

    //testProc.lto = .full;

    b.installArtifact(testProc);
}