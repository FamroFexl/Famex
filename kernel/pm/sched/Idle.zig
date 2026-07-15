const kernel = @import("kernel");

const scheduler = @import("scheduler.zig");

pub fn getScheduler() scheduler.Scheduler {
    return .{
        .policy = scheduler.Policy.FIFO,
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
    @panic("Cannot enqueue threads into Idle!");
}

fn dequeue(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
    @panic("Cannot dequeue threads from Idle!");
}

fn onSleep(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
    @panic("Cannot sleep threads from Idle!");
}

fn onWake(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
    @panic("Cannot wake threads from Idle!");
}

fn onYield(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
    @panic("Idle does not yield!");
}

fn onPreempt(sched : *const scheduler.Scheduler, thread : *kernel.Thread) void {
    _ = sched;
    _ = thread;
}

fn pickNext(sched : *const scheduler.Scheduler) ?*kernel.Thread {
    _ = sched;
    return &scheduler.schedData.getLocal().idle.base;
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
    @panic("Cannot set thread priority in Idle!");
}