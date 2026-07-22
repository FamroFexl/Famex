const kernel = @import("kernel");
const cpu = @import("arch").cpu;

pub fn sched_yield(state : *cpu.CpuState) i64 {
    _ = state;
    kernel.irqSave();
    defer kernel.irqRestore();

    kernel.cThread().yield();

    return 0;
}