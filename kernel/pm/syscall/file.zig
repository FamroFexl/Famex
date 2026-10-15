const kernel = @import("kernel");
const cast = kernel.cast;

const cpu = @import("arch").cpu;

const SysRet = @import("syscall.zig").SysRet;

const posix = @import("lib").posix;

const vfs = kernel.fs.vfs;

pub fn mkdir(state : *cpu.CpuState) SysRet {
    const path = state.getArgSys(0).*;
    const mode = state.getArgSys(1).*;
}