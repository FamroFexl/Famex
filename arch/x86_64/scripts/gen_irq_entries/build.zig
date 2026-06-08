const std = @import("std");
const log = std.log;

const cwd = "arch/x86_64/scripts/gen_irq_entries/";

pub fn exec(b : *std.Build, name : []const u8) std.Build.LazyPath {
    const gen_irq_entries_module = b.createModule(.{
        .root_source_file = b.path(cwd ++ "gen_irq_entries.zig"),
        .target = b.graph.host,
    });

    const gen_irq_entries = b.addExecutable(.{
        .name = "gen_irq_entries",
        .root_module = gen_irq_entries_module,
    });

    const gen_irq_entries_out = b.addRunArtifact(gen_irq_entries);
    const gen_irq_entries_file = gen_irq_entries_out.captureStdOut(.{.basename = name});

    return gen_irq_entries_file;

}