pub const ElfHdr = extern struct {
    id : ElfId,                 // ELF identification
    type : ET,                  // Object file type
    machine : MACHINE,       // Machine ID
    version : u32,              // Object file version
    entry : u32,                // Entry point address
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
        RISCV            = 243   // RISC-V
    };
};

pub const ElfSecHdr = extern struct {
    name : u32,             // Section name
    type : ST,    // Section type
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
        unused1 : u1,
        write : bool,   // Section contains writable data
        alloc : bool,   // Section is allocated in memory image of program
        unused2 : u1,
        execinstr : bool,  // Section contains executable instructions
        unused3 : u59,
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
        NULL,                // Unused entry
        LOAD,                // Loadable segment
        DYNAMIC,             // Dynamic linking tables
        INTERP,              // Program interpreter path name
        NOTE,                // Note sections
        SHLIB,               // Reserved
        PHDR,                // Program header table
    };

    pub const SegFlag = packed struct(u32) {
        unused1 : u1,
        execute : bool, // Execute permission
        write : bool,   // Write permission
        unused2 : u1,
        read : bool,    // Read permission
        unused3 : u27,
    };
};

pub const ElfDynTblEntry = extern struct {
    type : DT,   // Dynamic table entry type
    entry : packed union {
        val : u64,          // Used for integer values
        ptr : u64,          // Used for virtual addresses
    },

    /// Dynamic table type
    pub const DT = enum(i64) {
        NULL,                // Marks a dynamic array end
        NEEDED,              // String table offset of a needed library name
        PLTRELSZ,            // Procedure linkage table total size in bytes
        PLTGOT,              // Processor-dependent linkage table associated address
        HASH,                // Symbol hash table address
        STRTAB,              // Dynamic string table address
        SYMTAB,              // Dynamic symbol table address
        RELA,                // elf_rela_t table address
        RELASZ,              // elf_rela_t table total size
        RELAENT,             // elf_rela_t table entry size
        STRSZ,               // String table total size
        SYMENT,              // elf_sym_tbl_t entry size
        INIT,                // Initialization function address
        FINI,                // Termination function address
        SONAME,              // String table offset of this shared object's name
        RPATH,               // String table offset of a shared library search path string
        SYMBOLIC,            //
        REL,                 // elf_rel_t table address
        RELSZ,               // elf_rel_t table total size
        RELENT,              // elf_rel_t table entry size
        PLTREL,              // Relocation entry type used for procedure linkage
        DEBUG,               // Reserved for debugger
        TEXTDEL,             // Relocation table contains non-writable segments
        JMPREL,              // Procedure linkage table relocations address
        BIND_NOW,            // All relocations for this object should be processed before transferring control to the program
        INIT_ARRAY,          // Pointer to a pointer array of initialization functions
        FINI_ARRAY,          // Pointer to a pointer array of termination functions
        INIT_ARRAYSZ,        // Size of the pointer array of initialization functions
        FINI_ARRAYSZ,        // Size of the pointer array of termination functions
    };
};