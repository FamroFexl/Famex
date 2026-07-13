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
    enqueue : *const fn (*@This(), *kernel.Thread) void,
    dequeue : *const fn (*@This(), *kernel.Thread) void,
    onSleep : *const fn (*@This(), *kernel.Thread) void,
    onWake : *const fn (*@This(), *kernel.Thread) void,
    onYield : *const fn (*@This(), *kernel.Thread) void,
    onPreempt : *const fn (*@This(), *kernel.Thread) void,
    pickNext : *const fn (*@This()) ?*kernel.Thread,
    getTimeslice : *const fn (*@This(), *kernel.Thread) ?kernel.Time,
    setPriority : *const fn(*@This(), *kernel.Thread, anytype) void,
};

const SchedData = struct {
    spinlock : kernel.util.Spinlock,
    sched : [std.meta.fields(Policy).len]Scheduler,
    idle : kernel.pm.process.KThread,
    current : *kernel.pm.process.Thread,
    flags : Flags,
    // kstacktop
    timer : kernel.TimerEvent,  // Scheduler tick timer

    const Flags = packed struct {
        reschedule : bool,
    };
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
    const irqSaveDepth = kernel.io.irq.irqSaveDepth.getLocal().*;

    cThread().migrateSave();

    var state : kernel.CpuState = undefined;

    cThread().flags.loaded = false;

    // Save the current thread's execution state
    state.save();

    // This will only execute if the current thread is
    // being saved, not loaded
    if (!cThread().flags.loaded) {
        // Add runtime to the thread
        if (state.inKmode()) {
            kernel.pm.process.addKtime();
        }
        else {
            kernel.pm.process.addUtime();
        }

        // Switch to a new thread
        schedule(&state);

        // TODO Check for signals with the current thread
        if (!state.inKmode())
            kernel.pm.ipc.rcu.enterEqs();

        state.load();
        unreachable;
    }

    cThread().migrateRestore();

    // Restore interrupt state
    kernel.io.irq.irqSaveDepth.getLocal().* = irqSaveDepth;
}

fn loadThread(new : *kernel.Thread, state : *kernel.CpuState) void {
    const data = schedData.getLocal();

    data.current.context = state.*;

    data.current = new;
    state.* = new.context;

    if(new.container() == .uThread) {
        // Set syscall stack
        kernel.pm.process.perCpuStart.getLocal().syscallStack = kernel.bin.alignDown(cast.toInt(new.stack.start) + new.stack.size, 16);
    }
    else {

    }

    // Notifies inline saved threads which path to take
        new.flags.loaded = true;

    _ = new.owner.addr_space.rootPt.switchTo();
}

pub fn threadFromSched(node : *kernel.List.Node) *kernel.Thread {
    return @fieldParentPtr("schedLink", node);
}

pub fn schedule(state : *kernel.CpuState) void { kernel.noIrq();
    const data = schedData.getLocal();
    data.flags.reschedule = false;

    var next : *kernel.Thread = undefined;
    var timeslice : ?kernel.Time = null;
    {
        data.spinlock.lock();
        defer data.spinlock.unlock();

        for (0..std.meta.fields(Policy).len) |i| {
            const sched = &data.sched[i];

            if (sched.pickNext(sched)) |thread| {
                next = thread;
                timeslice = sched.getTimeslice(sched, thread);
            }
        }
    }

    loadThread(next, state);

    if (timeslice) |time| {
        data.timer.reset(time, false);
    }
}

pub fn setup() void {
    kernel.print("pm: Setting up Scheduler\n", .{});
    for (0..kernel.CPU_FEATURES.NUM_CPU_CORES) |i| {
        const localData = schedData.getGlobal(i);

        const idle = &localData.idle;
        //idle.base.tid = alloc id
        idle.base.owner = kernel.kernelProcess;
        idle.base.context.setPc(@intFromPtr(&cpu.idleEntry));
        idle.base.context.setStack(kernel.mm.memory.KERNEL_MEMORY.val);

        localData.current = &idle.base;

        localData.flags.reschedule = false;
        localData.spinlock.init();

        localData.timer.init(.MONOTONIC, .zero(), rescheduleTimer);

        localData.sched[@intFromEnum(Policy.FIFO)] = @import("Fifo.zig").getScheduler();
        localData.sched[@intFromEnum(Policy.RR)] = @import("RoundRobin.zig").getScheduler();
        localData.sched[@intFromEnum(Policy.OTHER)] = @import("Eevdf.zig").getScheduler();
        localData.sched[@intFromEnum(Policy.IDLE)] = @import("Idle.zig").getScheduler();
    }
}