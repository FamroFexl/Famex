const std = @import("std");

const acpica = @import("acpica/build.zig");
const linux = @import("linux/build.zig");
const posix = @import("posix/build.zig");

const cwd = "lib/";

pub fn module(b : *std.Build, options : *const std.Build.Module.CreateOptions, modules : *std.StringHashMap(*std.Build.Module)) *std.Build.Module {
    const lib_module = b.addModule("lib_module", options.*);
    lib_module.root_source_file = b.path(cwd ++ "root.zig");

    lib_module.addImport("acpica", acpica.module(b, options));

    const linuxModule = linux.module(b, options);
    linuxModule.addImport("lib", lib_module);

    lib_module.addImport("linux", linuxModule);

    const posixModule = posix.module(b, options);
    modules.put("posix", posixModule) catch unreachable;
    lib_module.addImport("posix", posixModule);

    return lib_module;
}