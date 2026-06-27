pub const util = @import("util/root.zig");
pub const mm = @import("mm/root.zig");
pub const pm = @import("pm/root.zig");
pub const io = @import("io/root.zig");
pub const config = @import("config.zig");

const arch = @import("arch");
const std = @import("std");
const lib = @import("lib");
const limine = lib.limine;

comptime {
    _ = io.acpi;
}

const LIMINE_REQUESTS_START linksection(".limine_requests_start") = limine.LIMINE_REQUESTS_START_MARKER;

pub var firmware_type linksection(".limine_requests") = limine.LimineFirmwareTypeRequest {};

pub var hhdm_request linksection(".limine_requests") = limine.LimineHhdmRequest {};

pub var mmap_request linksection(".limine_requests") = limine.LimineMemmapRequest {};

pub var module_request linksection(".limine_requests") = limine.LimineModuleRequest {};

pub var rsdp_request linksection(".limine_requests") = limine.LimineRsdpRequest {};

pub var executable_file_request linksection(".limine_requests") = limine.LimineExecutableFileRequest {};

pub var executable_address_request linksection(".limine_requests") = limine.LimineExecutableAddressRequest {};

// Defined by the architecture. and just for reference here
pub var smp_request : *limine.LimineMpRequest = undefined;

const LIMINE_REQUESTS_END linksection(".limine_requests_end") = limine.LIMINE_REQUESTS_END_MARKER;