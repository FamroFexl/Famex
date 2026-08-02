const kernel = @import("kernel");
const cast = kernel.cast;
const bin = kernel.bin;
const mem = kernel.mm.memory;

const posix = @import("lib").posix;

const arch = @import("arch");
const cpu = arch.cpu;

pub const SigData = struct {
    pendingMask : posix.signal.sigset_t = 0,
    pending : [posix.signal.sigNumNormal]posix.signal.siginfo_t = undefined,
    pendingRT : [posix.signal.sigNumRT]kernel.Queue = undefined,
    pendingRTNum : u64 = 0,
    spinlock : kernel.Spinlock = .create(),
};

const SigRTLink = struct {
    signal : posix.signal.siginfo_t,
    link : kernel.Queue.Node,
};

pub const SigFrame = struct {
    stackTop : u64,
    ucontext : posix.signal.ucontext_t,
    siginfo : posix.signal.siginfo_t,
    savedMask : posix.signal.sigset_t,
    retAddr : u64,
};

pub fn sigAlarmCallback(event : *kernel.TimerEvent) void {
    const process : *kernel.Process = @fieldParentPtr("sigAlarm", event);

    sigSend(.PROCESS, process, .{
        .si_signo = .SIGALRM,
    }) catch undefined;
}

/// SIG_DFL actions
fn sigDefault(signo : anytype) enum {TERMINATE, ABORT, IGNORE, STOP, CONTINUE} {
    return switch (signo) {
        .SIGALRM, .SIGHUP, .SIGINT, .SIGKILL, .SIGPIPE, .SIGTERM, .SIGUSR1, .SIGUSR2, .SIGVTALRM
        => .TERMINATE,
        .SIGABRT, .SIGBUS, .SIGFPE, .SIGILL, .SIGQUIT, .SIGSEGV, .SIGSYS, .SIGTRAP, .SIGXCPU, .SIGXFSZ
        => .ABORT,
        .SIGCHLD, .SIGWINCH, .SIGURG
        => .IGNORE,
        .SIGSTOP, .SIGTSTP, .SIGTTIN, .SIGTTOU,
        => .STOP,
        .SIGCONT,
        => .CONTINUE,
        else => .TERMINATE,
    };
}

/// Only wake the thread on a signal if it can receive it
pub fn checkForWake(uThread : *kernel.UThread) bool {
    uThread.sigData.spinlock.lock();
    const threadPending = uThread.sigData.pendingMask;
    const mask = uThread.sigMask;
    uThread.sigData.spinlock.unlock();

    if ((threadPending | ~mask) != 0)
        return true;

    uThread.base.owner.sigData.spinlock.lock();
    const procPending = uThread.base.owner.sigData.pendingMask;
    uThread.base.owner.sigData.spinlock.unlock();

    if ((procPending | ~mask) != 0)
        return true;

    return false;
}

pub fn sigSend(recType : enum {THREAD, PROCESS}, receiver : *anyopaque, signal : posix.signal.siginfo_t) error{RTQueueFull}!void {
    const signo = @intFromEnum(signal.si_signo);

    if (!posix.signal.sigValid(signo))
        @panic("Invalid signal number sent!");

    const sigData = if (recType == .THREAD) &cast.toPtr(*kernel.Thread, receiver).container().uThread.sigData else &cast.toPtr(*kernel.Process, receiver).sigData;

    if (signo >= posix.signal.SIGRTMIN) {
        const link = kernel.pmalloc(SigRTLink);

        sigData.spinlock.lock();

        if (sigData.pendingRTNum + 1 == posix.limits.SIGQUEUE_MAX) {
            sigData.spinlock.unlock();
            kernel.pfree(SigRTLink, link);
            return error.RTQueueFull;
        }

        sigData.pendingRTNum += 1;

        link.signal = signal;

        kernel.bin.setFlag(signo, &sigData.pendingMask);

        sigData.pendingRT[posix.signal.SIGRTMIN - cast.u64(signo)].push(&link.link);
    }
    else {
        sigData.spinlock.lock();

        if (kernel.bin.getFlag(signo, sigData.pendingMask))
            return;

        kernel.bin.setFlag(signo, &sigData.pendingMask);

        sigData.pending[@intCast(signo)] = signal;
    }

    sigData.spinlock.unlock();

    switch (recType) {
        .THREAD => {
            const uThread = cast.toPtr(*kernel.Thread, receiver).container().uThread;
            const check = checkForWake(uThread);

            uThread.base.spinlock.lock();
            defer uThread.base.spinlock.unlock();

            if (uThread.base.state == .INTERRUPTABLE and check) {
                uThread.base.state = .RUNNING;
                uThread.base.wakeReason = .SIGNAL_RECEIVED;
                uThread.base.wake();
            }
        },
        .PROCESS => {
            const process = cast.toPtr(*kernel.Process, receiver);

            process.spinlock.lock();
            defer process.spinlock.unlock();

            var threads = process.threads.iterator();
            while (threads.next()) |link| {
                const uThread = @as(*kernel.Thread, @fieldParentPtr("link", link)).container().uThread;

                const check = checkForWake(uThread);
                uThread.base.spinlock.lock();
                defer uThread.base.spinlock.unlock();

                if (uThread.base.state == .INTERRUPTABLE and check) {
                    uThread.base.state = .RUNNING;
                    uThread.base.wakeReason = .SIGNAL_RECEIVED;
                    uThread.base.wake();
                }
            }
        }
    }
}

fn sigActionReset(sigAction : *posix.signal.sigaction) void {
    sigAction.* = .{
        .sa_flags = .{},
        .sa_handler = .SIG_DFL,
        .sa_mask = 0,
    };
}

fn getSignal(sigData : *SigData, blocked : posix.signal.sigset_t) ?posix.signal.siginfo_t {
    sigData.spinlock.lock();

    const mask = sigData.pendingMask & ~blocked;
    if (mask != 0) {
        const signo = @ctz(mask);

        if (signo >= posix.signal.SIGRTMIN) {
            const rtQueue = &sigData.pendingRT[posix.signal.SIGRTMIN - signo];
            sigData.pendingRTNum -= 1;
            const link : *SigRTLink = @fieldParentPtr("link", rtQueue.pop().?);
            if (rtQueue.empty())
                kernel.bin.clearFlag(signo, &sigData.pendingMask);

            sigData.spinlock.unlock();

            const signal = link.signal;
            kernel.pfree(SigRTLink, link);

            return signal;
        }
        else {
            const signal = sigData.pending[signo];

            kernel.bin.clearFlag(signo, &sigData.pendingMask);

            sigData.spinlock.unlock();

            return signal;
        }
    }

    sigData.spinlock.unlock();
    return null;
}

/// Check for pending signals and handle them
pub fn sigHandle(state : *cpu.CpuState) void {
    const uThread = kernel.cThread().container().uThread;
    const process = uThread.base.owner;

    uThread.base.spinlock.lock();
    const threadMask = uThread.sigMask;
    var sigAltStack = uThread.sigAltStack;
    uThread.base.spinlock.unlock();

    const signal = getSignal(&uThread.sigData, threadMask)
        orelse getSignal(&process.sigData, threadMask)
        orelse return;

    process.spinlock.lock();
    const sigActionAddr = &process.sigAction[@intCast(@intFromEnum(signal.si_signo))];
    const sigAction = sigActionAddr.*;

    if (sigAction.sa_flags.SA_RESETHAND)
        sigActionReset(sigActionAddr);

    if (!sigAction.sa_flags.SA_SIGINFO and sigAction.sa_handler == .SIG_IGN) {
        process.spinlock.unlock();

        kernel.print("sig ignored\n", .{});

        return;
    }
    if (!sigAction.sa_flags.SA_SIGINFO and sigAction.sa_handler == .SIG_DFL) {
        const default = sigDefault(signal.si_signo);
        _ = default;

        kernel.print("sig default\n", .{});

        process.spinlock.unlock();

        return;
    }

    process.spinlock.unlock();

    var curStack : posix.signal.stack_t = undefined;

    // Use alt stack
    if (!sigAltStack.ss_flags.SS_ONSTACK        // Already on alt stack?
        and sigAction.sa_flags.SA_ONSTACK       // Alt stack requested?
        and !sigAltStack.ss_flags.SS_DISABLE    // Alt stack disabled?
    ) {
        sigAltStack.ss_flags.SS_ONSTACK = true;

        // Update thread stack
        uThread.base.spinlock.lock();
        uThread.sigAltStack.ss_flags.SS_ONSTACK = true;
        uThread.base.spinlock.unlock();

        curStack = sigAltStack;
    }
    else {
        curStack = .{
            .ss_flags = .{
                .SS_ONSTACK = false,
                .SS_DISABLE = sigAltStack.ss_flags.SS_DISABLE,
            },
            .ss_sp = @ptrFromInt(state.getStack()),
            .ss_size = 0,
        };
    }

    // Update signal mask
    uThread.base.spinlock.lock();
    uThread.sigMask |= sigAction.sa_mask;
    if (!sigAction.sa_flags.SA_NODEFER)
        uThread.sigMask |= bin.setBit(@intFromEnum(signal.si_signo));
    uThread.base.spinlock.unlock();

    const stackTop = cast.toInt(curStack.ss_sp) + curStack.ss_size;

    const ucontext : posix.signal.ucontext_t = .{
        .uc_link = null,
        .uc_stack = curStack,
        .uc_sigmask = threadMask | sigAction.sa_mask,
        .uc_mcontext = @bitCast(state.*),
    };

    arch.signal.pushSigFrame(state, &.{
        .stackTop = stackTop,
        .ucontext = ucontext,
        .siginfo = signal,
        .savedMask = threadMask,
        .retAddr = @intFromPtr(&kernel.pm.syscall.syscall.VDSO.sigReturn)
    }) catch {
        // Try SIGSEGV signal, else terminate process
    };

    state.setPc(@intFromEnum(sigAction.sa_handler));
}

pub fn sigreturn(state : *cpu.CpuState) kernel.pm.syscall.syscall.SysRet {
    var sigFrame : SigFrame = undefined;

    kernel.print("cur thread {*}\n", .{kernel.cThread()});

    arch.signal.popSigFrame(state, &sigFrame) catch {
        // Try SIGSEGV signal, else terminate process
    };

    const newState : *cpu.CpuState = cast.toPtr(*cpu.CpuState, &sigFrame.ucontext.uc_mcontext);
    if (newState.getStack() > mem.USER_MEMORY_END.val) {
        // Try SIGSEGV signal, else terminate process
        @panic("sigreturn stack error!");
    }

    newState.sanitizeRetFlags();

    state.* = newState.*;

    const uThread = kernel.cThread().container().uThread;
    uThread.base.spinlock.lock();
    uThread.sigMask = sigFrame.savedMask;
    uThread.base.spinlock.unlock();

    return .ok(0);
}