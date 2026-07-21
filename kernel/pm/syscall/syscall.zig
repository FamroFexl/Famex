const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;

const lib = @import("lib");
const errno = lib.posix.errno;

const cpu = @import("arch").cpu;


// Handle a specified syscall
pub export fn syscallHandler(state : *cpu.CpuState) void {
    //const uThread : *kernel.UThread = @fieldParentPtr("base", kernel.cThread());

    //uThread.flags.inSyscall = true;
    //defer uThread.flags.inSyscall = false;

    //kernel.pm.ipc.rcu.exitEqs();

    //kernel.pm.process.addUtime();

    //kernel.irqEnable();

    const sysNum = state.getRet().*;

    state.getRet().* = @bitCast(syscall(sysNum, state));

    //kernel.irqDisable();

    // Check for signals with the current thread

    //kernel.pm.process.addKtime();

    //kernel.pm.ipc.rcu.enterEqs();
    //
}

fn print(state : *cpu.CpuState) i64 {
    const ptr = cast.toPtr([*]const u8, state.getArgSys(0).*);
    const len = state.getArgSys(1).*;
    kernel.log.printChars(ptr, len);

    return 0;
}

fn yield(state : *cpu.CpuState) i64 {
    _ = state;
    kernel.cThread().yield();

    return 0;
}



fn syscall(sysNum : u64, state : *cpu.CpuState) i64 {
    return switch (sysNum) {
        1 => print(state),
        2 => yield(state),
        else => -errno.ENOSYS,
    };
}
