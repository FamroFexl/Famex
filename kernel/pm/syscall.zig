const cpu = @import("arch").cpu;

pub export fn syscallHandler(state : *cpu.CpuState) void {
    _ = state;
}