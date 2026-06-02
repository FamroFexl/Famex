pub const util = @import("util/root.zig");
pub const mm = @import("mm/root.zig");

const lib = @import("lib");
const arch = @import("arch");
const std = @import("std");
const limine = lib.limine;

export const limine_requests_start linksection(".limine_requests_start") = limine.LIMINE_REQUESTS_START_MARKER;

pub var firmware_type linksection(".limine_requests") = limine.limine_firmware_type_request {
    .id = limine.LIMINE_FIRMWARE_TYPE_REQUEST_ID,
    .revision = 3,
};

pub var hhdm_request linksection(".limine_requests") = limine.limine_hhdm_request {
    .id = limine.LIMINE_HHDM_REQUEST_ID,
    .revision = 3,
};

pub var mmap_request linksection(".limine_requests") = limine.limine_memmap_request {
    .id = limine.LIMINE_MEMMAP_REQUEST_ID,
    .revision = 3,
};

export const limine_requests_end linksection(".limine_requests_end") = limine.LIMINE_REQUESTS_END_MARKER;