const kernel = @import("kernel");

const lib = @import("lib");

const cpu = @import("arch").cpu;

pub const Syscall = enum {

};

// Handle a specified syscall
pub export fn syscallHandler(state : *cpu.CpuState) void {
    const uThread : *kernel.UThread = @fieldParentPtr("base", kernel.cThread());

    uThread.flags.inSyscall = true;
    defer uThread.flags.inSyscall = false;

    kernel.pm.ipc.rcu.exitEqs();

    kernel.pm.process.addUtime();

    kernel.irqEnable();

    const sysNum = state.getRet().*;

    if (sysNum >= @typeInfo(Syscall).@"enum".fields.len) {
        state.getRet().* = @bitCast(-@as(i64, lib.posix.errno.ENOSYS));
        kernel.irqDisable();
        return;
    }

    // const ret : i64 = syscalls[sysNum](state);
    // state.getRet().* = ret;

    kernel.irqDisable();

    // Check for signals with the current thread

    kernel.pm.process.addKtime();

    kernel.pm.ipc.rcu.enterEqs();
}