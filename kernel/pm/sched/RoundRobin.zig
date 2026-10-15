const kernel = @import("kernel");
const cast = kernel.cast;

const scheduler = @import("scheduler.zig");
const Fifo = @import("Fifo.zig");

fifo : Fifo,

pub fn getScheduler() scheduler.Scheduler {
    const new = kernel.pmalloc(@This());
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
    return cast.toPtr(*@This(), data);
}

fn enqueue(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    Fifo.enqueue(sched, thread);
}

fn dequeue(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    Fifo.dequeue(sched, thread);
}

fn onSleep(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    Fifo.onSleep(sched, thread);
}

fn onWake(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    Fifo.onWake(sched, thread);
}

fn onYield(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    Fifo.onYield(sched, thread);
}

fn onPreempt(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    const this = getRR(sched.data);

    const priority = thread.sched.priority;

    this.fifo.spinlock.lock();
    defer this.fifo.spinlock.unlock();

    this.fifo.priority[priority].insertFront(thread);
}

fn pickNext(sched : *const scheduler.Scheduler) ?*kernel.Thread {
    return Fifo.pickNext(sched);
}

fn getTimeslice(sched : *const scheduler.Scheduler, thread : *kernel.Thread) ?kernel.Time {
    _ = sched;
    _ = thread;
    return kernel.config.ROUND_ROBIN_TIMESLICE;
}

fn setPriority(sched : *const scheduler.Scheduler, thread : *kernel.Thread, newPriority : anytype) void {
    Fifo.setPriority(sched, thread, newPriority);
}

