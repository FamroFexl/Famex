const builtin = @import("builtin");

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

pub const LimineMemmapType = enum(u8) {
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

pub const LIMINE_PAGING_MODE_X86_64_4LVL = 0;
pub const LIMINE_PAGING_MODE_X86_64_5LVL = 1;

pub const LIMINE_PAGING_MODE_AARCH64_4LVL = 0;
pub const LIMINE_PAGING_MODE_AARCH64_5LVL = 1;

pub const LIMINE_PAGING_MODE_RISCV_SV39 = 0;
pub const LIMINE_PAGING_MODE_RISCV_SV48 = 1;
pub const LIMINE_PAGING_MODE_RISCV_SV57 = 2;

pub const LiminePagingModeResponse = extern struct {
    revision : u64,
    mode : u64,
};

pub const LiminePagingModeRequest = extern struct {
    id : LimineReqId = req_id(0x95c1a0edab0944cb, 0xa4e5cb3842f7488a),
    revision : u64 = LIMINE_REVISION,
    response : *LiminePagingModeResponse = undefined,
    mode : u64,
    max_mode : u64,
    min_mode : u64,
};

pub const LimineMpInfoX86 = extern struct {
    processor_id : u32,
    lapic_id : u32,
    reserved : u64,
    goto_address : u64,
    extra_argument : u64,
};

pub const LimineMpInfoAarch = extern struct {
    processor_id : u32,
    reserved1 : u32,
    mpidr : u64,
    reserved : u64,
    goto_address : u64,
    extra_argument : u64,
};

pub const LimineMpInfoRiscv = extern struct {
    processor_id : u64,
    hartid : u64,
    reserved : u64,
    goto_address : u64,
    extra_argument : u64,
};

const InfoUnion = extern union {
    x86 : [*]*LimineMpInfoX86,
    aarch : [*]*LimineMpInfoAarch,
    riscv : [*]*LimineMpInfoRiscv,
};

pub const LimineMpResponseX86 = extern struct {
    revision : u64,
    flags : u32,
    bsp_lapic_id : u32,
    cpu_count : u64,
    cpus : InfoUnion,
};

pub const LimineMpResponseAarch = extern struct {
    revision : u64,
    flags : u64,
    bsp_mpidr : u64,
    cpu_count : u64,
    cpus : InfoUnion,
};

pub const LimineMpResponseRiscv = extern struct {
    revision : u64,
    flags : u64,
    bsp_hartid : u64,
    cpu_count : u64,
    cpus : InfoUnion,
};

pub const LIMINE_MP_REQUEST_X86_64_X2APIC = 1;

pub const LimineMpRequest = extern struct {
    id : LimineReqId = req_id(0x95a67b819a1b857e, 0xa0b61b723b6a73e0),
    revision : u64 = LIMINE_REVISION,
    response : extern union {
        x86 : *LimineMpResponseX86,
        aarch : *LimineMpResponseAarch,
        riscv : *LimineMpResponseRiscv,
    },
    flags : u64,
};

pub const LimineInternalModuleFlags = enum(u64) {
    REQUIRED = 0,
    COMPRESSED = 1,
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
    id : LimineReqId = req_id(0x3e7e279702be32af, 0xca1c4f3bd1280cee),
    revision : u64 = LIMINE_REVISION,
    response : ?*LimineModuleResponse = null,

    // Request revision 1
    internal_module_count : u64 = undefined,
    internal_modules : [*]*LimineInternalModule = undefined,
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