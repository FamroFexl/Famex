const std = @import("std");

const cpu = @import("arch").cpu;

const kernel = @import("kernel");
const cast = kernel.cast;

pub const Policy = enum(u8) {
    FIFO = 0,       // First in-first out (FIFO) scheduling policy.
    RR = 1,         // Round robin scheduling policy.
    OTHER = 2,      // Primary and default scheduling policy (EEVDF)
    IDLE = 3,
};

pub const Scheduler = struct {
    policy : Policy,
    data : *anyopaque,
    enqueue : *const fn (*const @This(), *kernel.Thread) void,
    dequeue : *const fn (*const @This(), *kernel.Thread) void,
    onSleep : *const fn (*const @This(), *kernel.Thread) void,
    onWake : *const fn (*const @This(), *kernel.Thread) void,
    onYield : *const fn (*const @This(), *kernel.Thread) void,
    onPreempt : *const fn (*const @This(), *kernel.Thread) void,
    pickNext : *const fn (*const @This()) ?*kernel.Thread,
    getTimeslice : *const fn (*const @This(), *kernel.Thread) ?kernel.Time,
    setPriority : *const fn(*const @This(), *kernel.Thread, anytype) void,
};

const SchedData = struct {
    spinlock : kernel.util.Spinlock,
    sched : std.EnumArray(Policy, Scheduler),
    idle : kernel.pm.process.KThread,
    current : *kernel.pm.process.Thread,
    flags : packed struct {
        reschedule : bool,
    },
    timer : kernel.TimerEvent,  // Scheduler tick timer
};

fn rescheduleTimer(event : *kernel.TimerEvent) void {
    _ = event;
    schedData.getLocal().flags.reschedule = true;
}

pub const schedData = kernel.pm.process.PerCpuStat(SchedData, opaque {});

pub fn cThread() *kernel.pm.process.Thread {
    return schedData.getLocal().current;
}

pub fn switchThread() void { kernel.noIrq();
    cThread().migrateSave();

    var state : kernel.CpuState = undefined;

    // Save the current thread's execution state
    // If true, we are saving not loading
    if (state.save()) {
        // Add runtime to the thread
        if (state.inKmode()) {
            kernel.pm.process.addKtime();
        }
        else {
            kernel.pm.process.addUtime();
        }

        // Get a new thread
        schedule(&state);

        kernel.pm.signal.sigHandle(&state);

        if (!state.inKmode())
            kernel.pm.ipc.rcu.enterEqs();

        // Switch to the new thread
        state.load();
        unreachable;
    }

    cThread().migrateRestore();
}

fn loadThread(new : *kernel.Thread, state : *kernel.CpuState) void {
    const data = schedData.getLocal();

    data.current.context = state.*;
    data.current = new;
    state.* = new.context;

    kernel.io.irq.irqSaveDepth.getLocal().* = &new.irqSaveDepth;

    const perCpuStart = kernel.pm.process.perCpuStart.getLocal();
    if(new.container() == .uThread) {
        // Set syscall stack
        perCpuStart.syscallStack = kernel.bin.alignDown(cast.toInt(new.stack.start) + new.stack.size, 16);
    }
    else {

    }

    perCpuStart.hasFpuState = new.fpuContext != null;

    _ = new.owner.addrSpace.rootPt.switchTo();
}

pub fn threadFromSched(node : *kernel.List.Node) *kernel.Thread {
    return @fieldParentPtr("schedLink", node);
}

pub fn schedule(state : *kernel.CpuState) void { kernel.noIrq(); kernel.util.locks.noLocksHeld();
    const data = schedData.getLocal();
    data.flags.reschedule = false;

    var next : *kernel.Thread = undefined;
    var timeslice : ?kernel.Time = null;
    {
        data.spinlock.lock();
        defer data.spinlock.unlock();

        for (0..std.meta.fields(Policy).len) |i| {
            const sched = &data.sched.get(@enumFromInt(i));

            if (sched.pickNext(sched)) |thread| {
                next = thread;
                timeslice = sched.getTimeslice(sched, thread);
                break;
            }
        }
    }

    if (next != cThread()) {
        loadThread(next, state);
    }

    if (timeslice) |time| {
        data.timer.reset(time, false);
    }
}

pub fn reschedule() void {
    const data = schedData.getLocal();

    data.spinlock.lock();
    data.flags.reschedule = true;
    data.spinlock.unlock();
}

fn createIdle(idle : *kernel.KThread) void {
    idle.* = .{.base = .{
        .owner = kernel.kernelProcess,
    }};
    idle.base.context.init();
    idle.base.context.setPc(@intFromPtr(&cpu.idleEntry));
    idle.base.context.setStack(kernel.mm.memory.KERNEL_MEMORY.val);
    idle.base.sched.policy = .IDLE;
}

pub fn setup() void {
    kernel.print("pm: Setting up Scheduler\n", .{});
    for (0..kernel.CPU_FEATURES.NUM_CPU_CORES) |i| {
        const localData = schedData.getGlobal(i);

        createIdle(&localData.idle);
        localData.current = &localData.idle.base;

        localData.flags.reschedule = false;
        localData.spinlock.init();

        localData.timer.init(.MONOTONIC, .zero(), rescheduleTimer);

        localData.sched.set(.FIFO, @import("Fifo.zig").getScheduler());
        localData.sched.set(.RR, @import("RoundRobin.zig").getScheduler());
        localData.sched.set(.OTHER, @import("Eevdf.zig").getScheduler());
        localData.sched.set(.IDLE, @import("Idle.zig").getScheduler());
    }
}