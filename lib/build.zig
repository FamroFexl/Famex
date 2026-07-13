const std = @import("std");

const acpica = @import("acpica/build.zig");
const linux = @import("linux/build.zig");
const posix = @import("posix/build.zig");

const cwd = "lib/";

pub fn module(b : *std.Build, options : *const std.Build.Module.CreateOptions) *std.Build.Module {
    const lib_module = b.addModule("lib_module", options.*);
    lib_module.root_source_file = b.path(cwd ++ "root.zig");

    lib_module.addImport("acpica", acpica.module(b, options));

    const linuxModule = linux.module(b, options);
    linuxModule.addImport("lib", lib_module);
    lib_module.addImport("linux", linuxModule);

    lib_module.addImport("posix", posix.module(b, options));

    return lib_module;
}