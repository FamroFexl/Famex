pub const PROT = packed struct(u32) {
    READ : bool,    // Page can be read.
    WRITE : bool,   // Page can be written.
    EXEC : bool,     // Page can be executed.
    _pad1 : u29 = undefined,
};

pub const MAP = packed struct(u32) {
    ANONYMOUS : bool,   // Map anonymous memory.
    FIXED : bool,       // Interpret addr exactly.
    PRIVATE : bool,     // Changes are private.
    SHARED : bool,      // Share changes.
    _pad1 : u28 = undefined,
};

pub const MS = packed struct(u32) {
    ASYNC : bool,       // Perform asynchronous writes.
    INVALIDATE : bool,  // Invalidate mappings.
    SYNC : bool,        // Perform synchronous writes.
    _pad1 : u29 = undefined,
};

pub const MCL = packed struct(u32) {
    CURRENT : bool,     // Lock currently mapped pages.
    FUTURE : bool,      // Lock pages that become mapped.
    _pad1 : u30 = undefined,
};

pub const POSIX_TYPED_MEM = packed struct {
    ALLOCATE : bool,            // Allocate on mmap().
    ALLOCATE_CONTIG : bool,     // Allocate contiguously on mmap().
    MAP_ALLOCATABLE : bool,     // Map on mmap(), without affecting allocatability.
    _pad1 : u29 = undefined,
};