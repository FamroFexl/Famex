const kernel = @import("kernel");

pub const Fat = kernel.fs.vfs.FileSystemOps {
};

const BiosParamBlock = extern struct {
    BS_jmpBoot                      : [3]u8,    // Jump instruction to boot code.
    BS_OEMName                      : [8]u8,    // OEM Name Identifier.
    BPB_BytsPerSec                  : [2]u8,    // Count of bytes per sector. Can only be pow2 from 512 to 4096.
    BPB_SecPerClus                  : u8,       // Number of sectors per allocation unit. Can only be 1 and pow2 from 2 to 128.
    BPB_RsvdSecCnt                  : [2]u8,    // Number of reserved sectors.
    BPB_NumFATs                     : u8,       // The count of file allocation tables (FATs) on the volume.
    BPB_RootEntCnt                  : [2]u8,    // The count of 32-byte directory entries in the root directory if FAT12 or FAT16, 0 if FAT32.
    BPB_TotSec16                    : [2]u8,    // The old 16-bit total count of sectors on the volume.
    BPB_Media                       : u8,       // Can only be 0xF0, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, and 0xFF
    BPB_FATSz16                     : [2]u8,    // The FAT12/FAT16 16-bit count of sectors occupied by one FAT. 0 if FAT32.
    BPB_SecPerTrk                   : [2]u8,    // Sectors per track for interrupt 0x13.
    BPB_NumHeads                    : [2]u8,    // Number of heads for interrupt 0x13.
    BPB_HiddSec                     : [4]u8,    // Count of hidden sectors preceding the partition that contains this FAT volume.
    BPB_TotSec32                    : [4]u8,    // the new 32-bit total count of sectors on the volume. non-0 if FAT32.
    ext : union(enum) {
        // For FAT12 and FAT16
        fat16 : extern struct {
            BS_DrvNum               : u8,       // Interrupt 0x13 drive number. Can only be 0x80 or 0x00.
            BS_Reserved1            : u8,       // Reserved. Set value to 0x0.
            BS_BootSig              : u8,       // Extended boot signature. Set to 0x29 if the next two fields are not 0.
            BS_VolID                : [4]u8,    // Volume serial number.
            BS_VolLab               : [11]u8,   // Volume label.
            BS_FilSysType           : [8]u8,    // Can only be “FAT12 ”, “FAT16 ”, or “FAT”.
            _zero1                  : [448]u8,  // Set to 0x00.
        },
        fat32 : extern struct {
            BPB_FATSz32             : [4]u8,    // The FAT32 32-bit count of sectors occupied by one FAT.
            BPB_ExtFlags            : [2]u8,    // See ExtFlags struct below.
            BPB_FSVer               : [2]u8,    // Must be set to 0x0.
            BPB_RootClus            : [4]u8,    // The cluster number of the first cluster of the root directory. 2 or the first usable after.
            BPB_FSInfo              : [2]u8,    // Sector number of FSINFO structure in the reserved area of the FAT32 volume.
            BPB_BkBootSec           : [2]u8,    // The sector number in the reserved area of the volume of a copy of the boot record. Can only be 0 or 6.
            BPB_Reserved            : [12]u8,   // Must be set to 0x0.
            BS_DrvNum               : u8,       // Interrupt 0x13 drive number. Can only be 0x80 or 0x00.
            BS_Reserved1            : u8,       // Reserved. Set value to 0x0.
            BS_BootSig              : u8,       // Extended boot signature. Set to 0x29 if the next two fields are not 0.
            BS_VolID                : [4]u8,    // Volume serial number.
            BS_VolLab               : [11]u8,   // Volume label.
            BS_FilSysType           : [8]u8,    // Can only be “FAT12 ”, “FAT16 ”, or “FAT”.
            _zero1                  : [420]u8,  // Set to 0x00.
        },
    },
    Signature_word                  : [2]u8,    // Set to [0] 0x55 and [1] 0xAA.
};

const ExtFlags = packed struct(u16) {
    active      : u4,   // Zero-based number of active FAT. Only valid if mirroring is disabled.
    _rsvd1      : u3,
    unmirrored  : bool, // FAT is mirrored (0) or only one FAT is active (1)
    _rsvd2      : u8,
};

const block : BiosParamBlock = undefined;