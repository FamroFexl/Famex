const std = @import("std");

const cpu = @import("arch").cpu;

const kernel = @import("kernel");

pub const Policy = enum {
    FIFO,       // First in-first out (FIFO) scheduling policy.
    RR,         // Round robin scheduling policy.
    OTHER,      // Primary and default scheduling policy (CFS)
    IDLE,
};

pub const Scheduler = struct {
    policy : Policy,
    data : *anyopaque,
    enqueue : *const fn (*@This(), *kernel.ThreadBase) void,
    dequeue : *const fn (*@This(), *kernel.ThreadBase) void,
    onSleep : *const fn (*@This(), *kernel.ThreadBase) void,
    onWake : *const fn (*@This(), *kernel.ThreadBase) void,
    onYield : *const fn (*@This(), *kernel.ThreadBase) void,
    onPreempt : *const fn (*@This(), *kernel.ThreadBase) void,
    pickNext : *const fn (*@This()) ?*kernel.ThreadBase,
    getTimeslice : *const fn (*@This(), *kernel.ThreadBase) ?kernel.Time,
    setPriority : *const fn(*@This(), *kernel.ThreadBase, anytype) void,
};

const SchedData = struct {
    spinlock : kernel.util.Spinlock,
    sched : [std.meta.fields(Policy).len]Scheduler,
    idle : *kernel.pm.process.ThreadBase,
    current : *kernel.pm.process.ThreadBase,
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

pub const schedData = kernel.pm.process.PerCpuStat(SchedData);

pub fn cThread() *kernel.pm.process.ThreadBase {
    return schedData.getLocal().current;
}

fn switchThread() void {
    std.debug.assert(!kernel.irqEnabled());

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
        schedule(state);

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

fn loadThread(new : *kernel.ThreadBase, state : *kernel.CpuState) void {
    const data = schedData.getLocal();

    data.current.context = state.*;

    data.current = new;
    // set kstack top
    state.* = new.context;

    // Notifies inline saved threads which path to take
    new.flags.loaded = true;

    kernel.mm.paging.switchPageTables(new.owner.addr_space.rootPt);
}

pub fn threadFromSched(node : *kernel.List.Node) *kernel.ThreadBase {
    return @fieldParentPtr("schedLink", node);
}

pub fn schedule(state : *kernel.CpuState) void {
    std.debug.assert(!kernel.irqEnabled());

    const data = schedData.getLocal();
    data.flags.reschedule = false;

    var next : *kernel.ThreadBase = undefined;
    var timeslice : ?kernel.Time = null;
    {
        data.spinlock.lock();
        defer data.spinlock.unlock();

        for (0..std.meta.fields(Policy).len) |i| {
            const sched = data.sched[i];
            next = sched.pickNext();

            if (sched.pickNext()) |thread| {
                next = thread;
                timeslice = sched.getTimeslice(thread);
            }
        }
    }

    loadThread(next, state);

    if (timeslice) |time| {
        data.timer.reset(time, false);
    }
}

pub fn setup() void {
    for (0..kernel.CPU_FEATURES.NUM_CPU_CORES) |i| {
        const localData = schedData.getGlobal(i);

        const idle = kernel.pmalloc(kernel.KThread);
        //idle.base.tid = alloc id
        idle.base.owner = kernel.kernelProcess;
        idle.base.context.setPc(cpu.idleEntry());
        idle.base.context.setStack(kernel.mm.memory.KERNEL_MEMORY.val);
        localData.idle = idle;

        localData.current = idle;

        localData.flags.reschedule = false;
        localData.spinlock.init();

        localData.timer.init(.MONOTONIC, .zero(), rescheduleTimer);


        localData.sched[@intFromEnum(Policy.FIFO)] = @import("Fifo.zig").getScheduler();
        localData.sched[@intFromEnum(Policy.RR)] = @import("RoundRobin.zig").getScheduler();
        localData.sched[@intFromEnum(Policy.OTHER)] = @import("Eevdf.zig").getScheduler();
        localData.sched[@intFromEnum(Policy.IDLE)] = @import("Idle.zig").getScheduler();
    }

    kernel.pm.time.setup();
}

// void setup_sched() {
//     sched_by_prio[0] = &sched_fifo;
//     sched_by_prio[1] = &sched_rr;
//     sched_by_prio[2] = &sched_idle;
//
//     sched_data = map_cpu_global(sizeof(sched_data_t), 8);
//
//     u64 cpu;
//     cpu_for_each(cpu) {
//         sched_data_t* sched = get_cpu_global(sched_data, cpu);
//         for (int j = 0; j < 3; j++) {
//             sched_by_prio[j]->sched_create(sched);
//         }
//
//         kthread_t* new_idle = pmalloc(sizeof(*new_idle));
//         new_idle->tid = dyn_bitmap_alloc(tids);
//         new_idle->owner = &kernel_proc;
//
//         // Set initial execution state
//         cpu_state_t* state = pmalloc(sizeof(*state));
//         new_idle->context = *state;
//         set_pc(&new_idle->context, idle_entry);
//         set_stack(&new_idle->context, KERNEL_MEMORY); // Thread is in kernel mode
//
//         list_insert_back(&kernel_proc.threads, &new_idle->link);
//
//         cpu_data_t* data = get_cpu_global(cpu_data, cpu);
//
//         sched->idle = (thread_t*) new_idle;
//         sched->next_timer.cpu_data = data;
//
//         sched->current = sched->idle;
//
//         setup_timer_tree(data);
//     }
// }