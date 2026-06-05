pub const util = @import("util/root.zig");
pub const mm = @import("mm/root.zig");
pub const pm = @import("pm/root.zig");
pub const config = @import("config.zig");

const lib = @import("lib");
const arch = @import("arch");
const std = @import("std");
const limine = lib.limine;

export const LimineRequestsStart linksection(".limine_requests_start") = limine.LIMINE_REQUESTS_START_MARKER;

pub var firmware_type linksection(".limine_requests") = limine.LimineFirmwareTypeRequest {};

pub var hhdm_request linksection(".limine_requests") = limine.LimineHhdmRequest {};

pub var mmap_request linksection(".limine_requests") = limine.LimineMemmapRequest {};

pub var executable_file_request linksection(".limine_requests") = limine.LimineExecutableFileRequest {};

pub var executable_address_request linksection(".limine_requests") = limine.LimineExecutableAddressRequest {};

export const LimineRequestsEnd linksection(".limine_requests_end") = limine.LIMINE_REQUESTS_END_MARKER;