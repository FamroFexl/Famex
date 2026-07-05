const kernel = @import("kernel");

const scheduler = @import("scheduler.zig");
const Fifo = @import("Fifo.zig");

fifo : Fifo,

pub fn getScheduler() scheduler.Scheduler {
    const new = kernel.pmalloc(@This());
    new.fifo.spinlock.init();
    new.fifo.spinlock.init();
    for (&new.fifo.priority) |*prio| {
        prio.init();
    }

    return .{
        .policy = scheduler.Policy.RR,
        .data = new,
        .enqueue = enqueue,
        .dequeue = dequeue,
        .onSleep = onSleep,
        .onWake = onWake,
        .onYield = onYield,
        .onPreempt = onPreempt,
        .pickNext = pickNext,
        .getTimeslice = getTimeslice,
        .setPriority = setPriority,
    };
}

fn getRR(data : *anyopaque) *@This() {
    return kernel.bin.castPtr(*@This(), data);
}

fn enqueue(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    Fifo.enqueue(sched, thread);
}

fn dequeue(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    Fifo.dequeue(sched, thread);
}

fn onSleep(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    Fifo.onSleep(sched, thread);
}

fn onWake(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    Fifo.onWake(sched, thread);
}

fn onYield(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    Fifo.onYield(sched, thread);
}

fn onPreempt(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    const this = getRR(sched.data);

    const priority = thread.sched.priority;

    this.fifo.spinlock.lock();
    defer this.fifo.spinlock.unlock();

    this.fifo.priority[priority].insertFront(&thread.schedLink);
}

fn pickNext(sched : *scheduler.Scheduler) ?*kernel.ThreadBase {
    return Fifo.pickNext(sched);
}

fn getTimeslice(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) ?kernel.Time {
    _ = sched;
    _ = thread;
    return kernel.config.ROUND_ROBIN_TIMESLICE;
}

fn setPriority(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase, newPriority : anytype) void {
    Fifo.setPriority(sched, thread, newPriority);
}

