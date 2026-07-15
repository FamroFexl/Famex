const kernel = @import("kernel");

const scheduler = @import("scheduler.zig");
const Fifo = @import("Fifo.zig");

pub fn getScheduler() scheduler.Scheduler {
    return .{
        .policy = scheduler.Policy.OTHER,
        .data = undefined,
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

fn enqueue(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
}

fn dequeue(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
}

fn onSleep(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
}

fn onWake(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
}

fn onYield(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
}

fn onPreempt(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
}

fn pickNext(sched : *const scheduler.Scheduler) ?*kernel.Thread {
    _ = sched;
    return null;
}

fn getTimeslice(sched : *const scheduler.Scheduler, thread : *kernel.Thread) ?kernel.Time {
    _ = sched;
    _ = thread;
    return null;
}

fn setPriority(sched : *const scheduler.Scheduler, thread : *kernel.Thread, newPriority : anytype) void {
    _ = sched;
    _ = thread;
    _ = newPriority;
}