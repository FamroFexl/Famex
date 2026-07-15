const std = @import("std");

const builtin = @import("builtin");

pub const ElfHdr = extern struct {
    id : ElfId,                 // ELF identification
    type : ET,                  // Object file type
    machine : MACHINE,          // Machine ID
    version : u32,              // Object file version
    entry : u64,                // Entry point address
    ph_off : u64,               // Program header offset
    sh_off : u64,               // Section header offset
    flags : u32,                // Processor-specific flags
    eh_size : u16,              // ELF header size
    ph_ent_size : u16,          // Size of program header entry
    ph_num : u16,               // Number of program header entries
    sh_ent_size : u16,          // Size of section header entry
    sh_num : u16,               // Number of section header entries
    sh_str_ndx : u16,           // Section name string table index

    pub const ElfId = extern struct {
        magic : [4]u8,
        class : CLASS,
        data : DATA,
        version : u8,
        os : OSABI,
        abi : u8,
        padding : [7]u8,

        pub const MAGIC : [4]u8 = "\x7fELF";

        /// Object file class
        pub const CLASS = enum(u8) {
            NONE = 0,    // Invalid class
            C32 = 1,     // 32-bit objects
            C64 = 2      // 64-bit objects
        };

        /// Data encoding
        pub const DATA = enum(u8) {
            NONE = 0,   // Invalid data encoding
            LSB = 1,    // Least Significant Byte
            MSB = 2     // Most Significant Byte
        };

        /// OS/ABI type
        pub const OSABI = enum(u8) {
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

    /// Object file type
    pub const ET = enum(u16) {
        NONE = 0,    // No file type
        REL = 1,     // Relocatable object file
        EXEC = 2,    // Executable file
        DYN = 3,     // Shared object file
        CORE = 4,    // Core file
    };

    /// Machine type
    pub const MACHINE = enum(u16) {
        NONE             = 0,    // No machine
        X86_32           = 3,    // Intel x86-32
        AARCH32          = 40,   // AARCH32 (ARM32)
        X86_64           = 62,   // Intel x86-64
        AARCH64          = 183,  // AARCH64 (ARM64)
        RISCV            = 243,   // RISC-V
    };

    /// Check if ELF signature matches
    pub fn isElf(hdr : *@This()) bool {
        return std.mem.eql(u8, &hdr.id.magic, "\x7fELF");
    }

    pub fn isValid(hdr : *@This()) bool {
        if (hdr.id.class != .C64 and hdr.id.data != .LSB)
            return false;

        return hdr.machine == switch (builtin.cpu.arch) {
            .x86_64 => .X86_64,
            .aarch64 => .AARCH64,
            .riscv64 => .RISCV,
            else => unreachable,
        };
    }

    /// Get a program header by it's index
    pub fn getPhdrByIndex(hdr : *@This(), num : anytype) ?*ElfPrgHdr {
        if (num >= hdr.ph_num) return null;
        return @ptrFromInt(@intFromPtr(hdr) + hdr.ph_off + hdr.ph_ent_size * num);
    }

    /// Get a section header by it's index
    pub fn getShdrByIndex(hdr : *@This(), num : anytype) ?*ElfSecHdr {
        if (num >= hdr.sh_num) return null;
        return @ptrFromInt(@intFromPtr(hdr) + hdr.sh_off + hdr.sh_ent_size * num);
    }

    /// Get a section header by it's name
    pub fn getShdrByName(hdr : *@This(), comptime str : []const u8) ?*ElfSecHdr {
        const hdr_int = @intFromPtr(hdr);
        const str_shdr = hdr.getShdrByIndex(hdr.sh_str_ndx).?;
        for (0..hdr.sh_num) |i| {
            const shdr = hdr.getShdrByIndex(i).?;
            if (shdr.name > str_shdr.size)
                continue;

            const name : [*:0]u8 = @ptrFromInt(hdr_int + str_shdr.offset + shdr.name);
            const slice = std.mem.sliceTo(name, 0);

            if (std.mem.eql(u8, slice, str))
                return shdr;
        }

        return null;
    }
};

pub const ElfSecHdr = extern struct {
    name : u32,             // Section name offset
    type : ST,              // Section type
    flag : SecFlag,         // Section attributes
    addr : u64,             // Virtual address in memory
    offset : u64,           // Offset in file
    size : u64,             // Size of section
    link : u32,             // Link to other section
    info : u32,             // Misc info
    addr_align : u64,       // Address alignment boundary
    ent_size : u64,         // Size of entries, if section has table

    /// Section table type
    pub const ST = enum(u32) {
        NULL,       // Unused section header
        PROGBITS,   // Program-defined information
        SYMTAB,     // Linker symbol table
        STRTAB,     // A string table
        RELA,       // "Rela" type relocation entries
        HASH,       // A symbol hash table
        DYNAMIC,    // Dynamic linking tables
        NOTE,       // Note information
        NOBITS,     // Uninitialized space
        REL,        // "Rel" type relocation entries
        SHLIB,      // Reserved
        DYNSYM,     // Dynamic loader symbol table
    };

    pub const SecFlag = packed struct(u64) {
        write : bool,   // Section contains writable data
        alloc : bool,   // Section is allocated in memory image of program
        execinstr : bool,  // Section contains executable instructions
        unused1 : u61,
    };
};

pub const ElfSymHdr = extern struct {
    name : u32,             // Symbol name
    other : u8,             // Reserved
    type : STT,             // Symbol type
    binding : STB,          // Symbol binding
    sh_ndx : u16,           // Section table index
    value : u64,            // Symbol value
    size : u64,             // Size of object

    /// Symbol binding type
    pub const STB = enum(u4) {
        LOCAL,          // Not visible outside object file
        GLOBAL,         // Global symbol, visible to all object files
        WEAK,           // Global symbol, but with lower precedence than STB_GLOBAL
    };

    /// Symbol type
    pub const STT = enum(u4) {
        NOTYPE,         // No type specified (absolute symbol)
        OBJECT,         // Data object
        FUNC,           // Function entry point
        SECTION,        // Symbol associated with section
        FILE,           // Source file associated with the object file
    };
};

pub const ElfPrgHdr = extern struct {
    type : PT,          // Segment type
    flags : SegFlag,    // Segment attributes
    offset : u64,       // Offset in file
    vaddr : u64,        // Virtual memory address
    paddr : u64,        // Reserved
    file_sz : u64,      // Segment size in file
    mem_sz : u64,       // Segment size in memory
    alignment : u64,    // Segment alignment

    /// Program table type
    pub const PT = enum(u32) {
        NULL = 0,                // Unused entry
        LOAD = 1,                // Loadable segment
        DYNAMIC = 2,             // Dynamic linking tables
        INTERP = 3,              // Program interpreter path name
        NOTE = 4,                // Note sections
        SHLIB = 5,               // Reserved
        PHDR = 6,                // Program header table
        GNU_STACK = 0x6474e551,  // Specifies if stack is executable in flags.execute only
    };

    pub const SegFlag = packed struct(u32) {
        execute : bool, // Execute permission
        write : bool,   // Write permission
        read : bool,    // Read permission
        unused3 : u29,
    };
};