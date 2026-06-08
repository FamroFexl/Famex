const std = @import("std");
const log = std.log;

const cwd = "arch/x86_64/scripts/gen_offsets/";

pub fn exec(b : *std.Build, arch_path : std.Build.LazyPath, name : []const u8) std.Build.LazyPath {
    const gen_offsets_module = b.createModule(.{
        .root_source_file = b.path(cwd ++ "gen_offsets.zig"),
        .target = b.graph.host,
    });

    gen_offsets_module.addAnonymousImport("reg", .{.root_source_file = arch_path});

    const gen_offsets = b.addExecutable(.{
        .name = "gen_offsets",
        .root_module = gen_offsets_module,
    });

    const gen_offsets_out = b.addRunArtifact(gen_offsets);
    const gen_offsets_file = gen_offsets_out.captureStdOut(.{.basename = name});

    return gen_offsets_file;
}