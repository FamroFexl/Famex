const posix = @import("lib").posix;
const cpu = @import("cpu.zig");

const kernel = @import("kernel");
const bin = kernel.bin;
const mem = kernel.mm.memory;

/// Push a signal frame onto the stack
pub fn pushSigFrame(state : *cpu.CpuState, sigFrame : *const kernel.pm.signal.SigFrame) error{CopyToUserFailed}!void {
    // Signo in arg 0
    state.getArg(0).* = bin.convert(u64, sigFrame.siginfo.si_signo);

    var stackTop = sigFrame.stackTop;

    stackTop -= @sizeOf(posix.signal.siginfo_t);

    // Copy siginfo
    if (mem.copyToUser(@ptrFromInt(stackTop), &sigFrame.siginfo, @sizeOf(posix.signal.siginfo_t)) != 0) {
        return error.CopyToUserFailed;
    }

    // Siginfo in arg 1
    state.getArg(1).* = stackTop;

    // Copy old mask to restore
    stackTop -= @sizeOf(posix.signal.sigset_t);
    if (mem.copyToUser(@ptrFromInt(stackTop), &sigFrame.savedMask, @sizeOf(posix.signal.sigset_t)) != 0) {
        return error.CopyToUserFailed;
    }

    // Copy ucontext
    stackTop -= @sizeOf(posix.signal.ucontext_t);

    if (mem.copyToUser(@ptrFromInt(stackTop), &sigFrame.ucontext, @sizeOf(posix.signal.ucontext_t)) != 0) {
        return error.CopyToUserFailed;
    }

    // Ucontext in arg 2
    state.getArg(2).* = stackTop;

    // Copy in return (sysV align for last push)
    stackTop = bin.alignDown(stackTop, 16) - 8;
    if (mem.copyToUser(@ptrFromInt(stackTop), &sigFrame.retAddr, @sizeOf(u64)) != 0) {
        return error.CopyToUserFailed;
    }

    state.setStack(stackTop);
}

/// Pop a signal frame from the stack
pub fn popSigFrame(state : *cpu.CpuState, sigFrame : *kernel.pm.signal.SigFrame) error{CopyFromUserFailed}!void {
    var stackTop = state.getStack();

    if (mem.copyFromUser(&sigFrame.ucontext, @ptrFromInt(stackTop), @sizeOf(posix.signal.ucontext_t)) != 0) {
        return error.CopyFromUserFailed;
    }

    stackTop += @sizeOf(posix.signal.ucontext_t);

    if (mem.copyFromUser(&sigFrame.savedMask, @ptrFromInt(stackTop), @sizeOf(posix.signal.sigset_t)) != 0) {
        return error.CopyFromUserFailed;
    }
}