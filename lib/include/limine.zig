pub const LIMINE_REQUESTS_START_MARKER : [4]u64 =  .{ 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 };
pub const LIMINE_REQUESTS_END_MARKER : [2]u64 = .{ 0xadc0e0531bb10d03, 0x9572709f31764c62 };

const LIMINE_COMMON_MAGIC : [2]u64 = .{0xc7b1dd30df4c8b88, 0x0a82e883a194f07b};

pub const LIMINE_REVISION : u64 = 3;

pub const LimineReqId = [4]u64;

fn req_id(id3 : u64, id4: u64) LimineReqId {
    return LIMINE_COMMON_MAGIC ++ .{id3, id4};
}

pub const LimineUuid = extern struct {
    a : u32,
    b : u16,
    c : u16,
    d : [8]u8,
};

pub const LimineFile = extern struct {
    revision : u64,
    address : *anyopaque,
    size : u64,
    path : [*]u8,
    string : [*]u8,
    media_type : u32,
    unused : u32,
    tftp_ip : u32,
    tftp_port : u32,
    partition_index : u32,
    mbr_disk_id : u32,
    gpt_disk_uuid : LimineUuid,
    gpt_part_uuid : LimineUuid,
    part_uuid : LimineUuid,
};

pub const LIMINE_FIRMWARE_TYPE = enum(u8) {
    X86BIOS,
    EFI32,
    EFI64,
    SBI
};

pub const LimineFirmwareTypeResponse = extern struct {
    revision : u64,
    firmware_type : u64,
};

pub const LimineFirmwareTypeRequest = extern struct {
    id : LimineReqId = req_id(0x8c2f75d90bef28a8, 0x7045a4688eac00c3),
    revision : u64 = LIMINE_REVISION,
    response : *LimineFirmwareTypeResponse = undefined,
};

pub const LimineHhdmResponse = extern struct {
    revision : u64,
    offset : u64,
};

pub const LimineHhdmRequest = extern struct {
    id : LimineReqId = req_id(0x48dcf1cb8ad2b852, 0x63984e959a98244b),
    revision : u64 = LIMINE_REVISION,
    response : *LimineHhdmResponse = undefined,
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

pub const LimineMemmapEntry = extern struct {
    base : u64,
    length : u64,
    type : u64,
};

pub const LimineMemmapResponse = extern struct {
    revision : u64,
    entry_count : u64,
    entries : [*]*LimineMemmapEntry,
};

pub const LimineMemmapRequest = extern struct {
    id : LimineReqId = req_id(0x67cf3d9d378a806f, 0xe304acdfc50c3c62),
    revision : u64 = LIMINE_REVISION,
    response : *LimineMemmapResponse = undefined,
};

pub const LIMINE_INTERNAL_MODULE_FLAGS = enum(u64) {
    required = 0,
    compressed = 1,
};

pub const LimineInternalModule = extern struct {
    path : [*]const u8,
    string : [*]const u8,
    flags : u64,
};

pub const LimineModuleResponse = extern struct {
    revision : u64,
    module_count : u64,
    modules : [*]*LimineFile,
};

pub const LimineModuleRequest = extern struct {
    id : req_id(0x3e7e279702be32af, 0xca1c4f3bd1280cee),
    revision : LIMINE_REVISION,
    response : *LimineModuleResponse = undefined,

    // Request revision 1
    internal_module_count : u64,
    internal_modules : [*]*LimineInternalModule,
};

pub const LimineExecutableFileResponse = extern struct {
    revision : u64,
    executable_file : *LimineFile,
};

pub const LimineExecutableFileRequest = extern struct {
    id : LimineReqId = req_id(0xad97e90e83f1ed67, 0x31eb5d1c5ff23b69),
    revision : u64 = LIMINE_REVISION,
    response : *LimineExecutableFileResponse = undefined,
};

pub const LimineExecutableAddressResponse = extern struct {
    revision : u64,
    physical_base : u64,
    virtual_base : u64,
};

pub const LimineExecutableAddressRequest = extern struct {
    id : LimineReqId = req_id(0x71ba76863cc55f63, 0xb2644a48c516a487),
    revision : u64 = LIMINE_REVISION,
    response : *LimineExecutableAddressResponse = undefined,
};