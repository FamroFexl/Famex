const Vaddr = @import("memory.zig").Vaddr;
const paging = @import("paging.zig");

pub const VmSpace = struct {
    //vm_lock : spinlock,
    //tree : maple_tree,
    //cpu_mask : cpu_mask,
    start : Vaddr,
    end : Vaddr,
    root_pt : *paging.Ptable,
};

pub const ElfId = extern struct {
    magic : [4]u8,
    class : OBJECT_FILE_CLASS,
    data : DATA_ENCODING,
    version : u8,
    os : OS_ABI_ID,
    abi : u8,
    padding : [7]u8,

    pub const OBJECT_FILE_CLASS = enum(u8) {
        CLASSNONE = 0,   // Invalid class
        CLASS32 = 1,     // 32-bit objects
        CLASS64 = 2      // 64-bit objects
    };

    pub const DATA_ENCODING = enum(u8) {
        DATANONE = 0,    // Invalid data encoding
        DATA2LSB = 1,    // Least Significant Byte
        DATA2MSB = 2     // Most Significant Byte
    };

    pub const OS_ABI_ID = enum(u8) {
        SYSV       = 0,    // UNIX System V ABI
        NETBSD     = 2,    // NetBSD
        LINUX      = 3,    // GNU/Linux
        SOLARIS    = 6,    // GNU/HURD
        FREEBSD    = 9,    // FreeBSD
        OPENBSD    = 12,   // OpenBSD
        ARM        = 97,   // ARM
        STANDALONE = 255
    };
};

pub fn setup_virt_mem_mgmt() void {

}