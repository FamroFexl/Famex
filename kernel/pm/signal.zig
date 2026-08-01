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

pub fn sigAlarmCallback(event : *kernel.TimerEvent) void {
    const process : *kernel.Process = @fieldParentPtr("sigAlarm", event);

    sigSend(.PROCESS, process, .{
        .si_signo = @intFromEnum(posix.signal.Signal.SIGALRM),
        .si_pid = process.pid,
        .si_uid = process.creds.ruid,
    }) catch undefined;
}

/// SIG_DFL actions
fn sigDefault(signo : anytype) enum {TERMINATE, ABORT, IGNORE, STOP, CONTINUE} {
    const signal = @as(posix.signal.Signal, @enumFromInt(signo));
    return switch (signal) {
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
pub fn checkForWake(thread : *kernel.Thread) bool {
    thread.sigData.spinlock.lock();
    const threadPending = thread.sigData.pendingMask;
    const mask = thread.sigMask;
    thread.sigData.spinlock.unlock();

    if ((threadPending | ~mask) != 0)
        return true;

    thread.owner.sigData.spinlock.lock();
    const procPending = thread.owner.sigData.pendingMask;
    thread.owner.sigData.spinlock.unlock();

    if ((procPending | ~mask) != 0)
        return true;

    return false;
}

pub fn sigSend(recType : enum {THREAD, PROCESS}, receiver : *anyopaque, signal : posix.signal.siginfo_t) error{RTQueueFull}!void {
    const signo = signal.si_signo;

    if (!posix.signal.sigValid(signo))
        @panic("Invalid signal number sent!");

    const sigData = if (recType == .THREAD) &cast.toPtr(*kernel.Thread, receiver).sigData else &cast.toPtr(*kernel.Process, receiver).sigData;

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
            const thread = cast.toPtr(*kernel.Thread, receiver);
            const check = checkForWake(thread);

            thread.spinlock.lock();
            defer thread.spinlock.unlock();

            if (thread.state == .INTERRUPTABLE and check) {
                thread.state = .RUNNING;
                thread.wakeReason = .SIGNAL_RECEIVED;
                thread.wake();
            }
        },
        .PROCESS => {
            const process = cast.toPtr(*kernel.Process, receiver);

            process.spinlock.lock();
            defer process.spinlock.unlock();

            var threads = process.threads.iterator();
            while (threads.next()) |link| {
                const thread : *kernel.Thread = @fieldParentPtr("link", link);

                const check = checkForWake(thread);
                thread.spinlock.lock();
                defer thread.spinlock.unlock();

                if (thread.state == .INTERRUPTABLE and check) {
                    thread.state = .RUNNING;
                    thread.wakeReason = .SIGNAL_RECEIVED;
                    thread.wake();
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
    const thread = kernel.cThread();
    const process = thread.owner;

    thread.spinlock.lock();
    const threadMask = thread.sigMask;
    var sigAltStack = thread.sigAltStack;
    thread.spinlock.unlock();

    const signal = getSignal(&thread.sigData, threadMask)
        orelse getSignal(&process.sigData, threadMask)
        orelse return;

    process.spinlock.lock();
    const sigActionAddr = &process.sigAction[@intCast(signal.si_signo)];
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
        thread.spinlock.lock();
        thread.sigAltStack.ss_flags.SS_ONSTACK = true;
        thread.spinlock.unlock();

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
    thread.spinlock.lock();
    thread.sigMask |= sigAction.sa_mask;
    if (!sigAction.sa_flags.SA_NODEFER)
        thread.sigMask |= bin.setBit(signal.si_signo);
    thread.spinlock.unlock();

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
    var sigFrame : arch.signal.SigFrame = undefined;

    arch.signal.popSigFrame(state, &sigFrame) catch {
        // Try SIGSEGV signal, else terminate process
    };

    const newState : *cpu.CpuState = cast.toPtr(*cpu.CpuState, &sigFrame.ucontext.uc_mcontext);
    if (newState.getStack() > mem.USER_MEMORY_END.val) {
        // Try SIGSEGV signal, else terminate process
        kernel.print("stack error!\n", .{});
    }

    newState.sanitizeRetFlags();

    state.* = newState.*;

    const thread = kernel.cThread();
    thread.spinlock.lock();
    thread.sigMask = sigFrame.savedMask;
    thread.spinlock.unlock();

    return .ok(0);
}