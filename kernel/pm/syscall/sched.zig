const kernel = @import("kernel");
const cast = kernel.cast;

const cpu = @import("arch").cpu;

const SysRet = @import("syscall.zig").SysRet;

const posix = @import("lib").posix;

pub fn sched_yield(state : *cpu.CpuState) SysRet {
    _ = state;
    kernel.irqSave();
    defer kernel.irqRestore();

    kernel.cThread().yield();

    return .ok(0);
}

// pub fn getpriority(state : *cpu.CpuState) SysRet {
//     const which : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(0).*)));
//     const who : posix.types.id_t = @truncate(state.getArgSys(1).*);
// }
//
// pub fn setpriority(state : *cpu.CpuState) SysRet {
//     const which : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(0).*)));
//     const who : posix.types.id_t = @truncate(state.getArgSys(1).*);
//     const value : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(2).*)));
// }

// pub fn getrlimit(state : *cpu.CpuState) SysRet {
//     const resource = kernel.bin.convert(posix.resource.RLimit, state.getArgSys(0).*);
//     const rlp = cast.toPtr(*allowzero posix.resource.rlimit, state.getArgSys(1).*);
//
//     switch (resource) {
//
//     }
// }
//
// pub fn setrlimit(state : *cpu.CpuState) SysRet {
//
// }