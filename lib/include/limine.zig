pub const LIMINE_REQUESTS_START_MARKER : [4]u64 =  .{ 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 };
pub const LIMINE_REQUESTS_END_MARKER : [2]u64 = .{ 0xadc0e0531bb10d03, 0x9572709f31764c62 };

pub const LIMINE_COMMON_MAGIC : [2]u64 = .{0xc7b1dd30df4c8b88, 0x0a82e883a194f07b};

pub const LIMINE_FIRMWARE_TYPE = enum(u8) {
    X86BIOS,
    EFI32,
    EFI64,
    SBI
};

pub const LIMINE_FIRMWARE_TYPE_REQUEST_ID : [4]u64 = LIMINE_COMMON_MAGIC ++ .{ 0x8c2f75d90bef28a8, 0x7045a4688eac00c3 };

pub const limine_firmware_type_response = struct {
    revision : u64,
    firmware_type : u64,
};

pub const limine_firmware_type_request = struct {
    id : [4]u64,
    revision : u64,
    response : *limine_firmware_type_response = undefined,
};

pub const LIMINE_HHDM_REQUEST_ID : [4]u64 = LIMINE_COMMON_MAGIC ++ .{ 0x48dcf1cb8ad2b852, 0x63984e959a98244b };

pub const limine_hhdm_response = struct {
    revision : u64,
    offset : u64,
};

pub const limine_hhdm_request = struct {
    id : [4]u64,
    revision : u64,
    response : *limine_hhdm_response = undefined,
};

pub const LIMINE_MEMMAP_TYPE = enum(u8) {
    USABLE,
    RESERVED,
    ACPI_RECLAIMABLE,
    ACPI_NVS,
    BAD_MEMORY,
    BOOTLOADER_RECLAIMABLE,
    EXECUTABLE_AND_MODULES,
    FRAMEBUFFER,
    RESERVED_MAPPED,
};

pub const LIMINE_MEMMAP_REQUEST_ID : [4]u64 = LIMINE_COMMON_MAGIC ++ .{0x67cf3d9d378a806f, 0xe304acdfc50c3c62 };

pub const limine_memmap_entry = struct {
    base : u64,
    length : u64,
    type : u64,
};

pub const limine_memmap_response = struct {
    revision : u64,
    entry_count : u64,
    entries : [*]*limine_memmap_entry,
};

pub const limine_memmap_request = struct {
    id : [4]u64,
    revision : u64,
    response : *limine_memmap_response = undefined,
};