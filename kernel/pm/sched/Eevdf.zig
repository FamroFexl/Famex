const kernel = @import("kernel");

const scheduler = @import("scheduler.zig");
const Fifo = @import("Fifo.zig");

pub fn getScheduler() scheduler.Scheduler {
    return .{
        .policy = scheduler.Policy.OTHER,
        .data = @ptrFromInt(0),
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

fn enqueue(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    _ = sched;
    _ = thread;
}

fn dequeue(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    _ = sched;
    _ = thread;
}

fn onSleep(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    _ = sched;
    _ = thread;
}

fn onWake(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    _ = sched;
    _ = thread;
}

fn onYield(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    _ = sched;
    _ = thread;
}

fn onPreempt(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    _ = sched;
    _ = thread;
}

fn pickNext(sched : *scheduler.Scheduler) ?*kernel.ThreadBase {
    _ = sched;
    return null;
}

fn getTimeslice(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) ?kernel.Time {
    _ = sched;
    _ = thread;
    return null;
}

fn setPriority(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase, newPriority : anytype) void {
    _ = sched;
    _ = thread;
    _ = newPriority;
}