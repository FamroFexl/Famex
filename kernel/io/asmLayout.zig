pub const PerCpuStart = struct {
    syscallStack : u64,     // Address of the syscall stack to use for syscall
    irqStack : u64,         // Stack of the dedicated IRQ stack we may switch to depending on irqNestDepth
    irqNestDepth : u8,      // Depth of IRQ handler nesting we are in
};