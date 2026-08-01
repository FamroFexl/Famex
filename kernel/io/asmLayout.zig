pub const PerCpuStart = struct {
    syscallStack : u64,     // Address of the syscall stack to use for syscall
    hasFpuState : bool,
};