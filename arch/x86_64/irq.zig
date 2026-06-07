pub const IrqFrame = packed struct {
    err : u64,      // Error code
    rip : u64,      // Program counter
    cs : u64,       // Code segment
    rflags : u64,   // CPU flags
    rsp : u64,      // Stack pointer
    ss : u64        // Stack segment
};