const kernel = @import("kernel");

const scheduler = @import("scheduler.zig");

priority : [kernel.config.SCHED_PRIORITY_MAX]kernel.List,
spinlock : kernel.Spinlock,

pub fn getScheduler() scheduler.Scheduler {
    const new = kernel.pmalloc(@This());
    new.spinlock.init();
    for (&new.priority) |*prio| {
        prio.init();
    }

    return .{
        .policy = scheduler.Policy.FIFO,
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

fn getFifo(data : *anyopaque) *@This() {
    return kernel.bin.castPtr(*@This(), data);
}

fn enqueue(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    const this = getFifo(sched.data);

    const priority = thread.sched.priority;

    this.spinlock.lock();
    defer this.spinlock.unlock();

    this.priority[priority].insertBack(&thread.schedLink);
}

fn dequeue(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    const this = getFifo(sched.data);

    const priority = thread.sched.priority;

    this.spinlock.lock();
    defer this.spinlock.unlock();

    // Check if the thread to remove is running. If so, stop it

    this.priority[priority].remove(&thread.schedLink);
}

fn onSleep(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    const this = getFifo(sched.data);

    this.dequeue(thread);
}

fn onWake(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    const this = getFifo(sched.data);

    this.enqueue(thread);
}

fn onYield(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    const this = getFifo(sched.data);

    const priority = thread.sched.priority;

    const list = this.priority[priority];

    this.spinlock.lock();
    defer this.spinlock.unlock();

    list.remove(&thread.schedLink);
    list.insertBack(&thread.schedLink);
}

fn onPreempt(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) void {
    _ = sched;
    _ = thread;
    @panic("FIFO threads cannot be preempted!");
}

fn pickNext(sched : *scheduler.Scheduler) ?*kernel.ThreadBase {
    const this = getFifo(sched.data);

    var i = this.priority.len;

    this.spinlock.lock();
    defer this.spinlock.unlock();

    while (i > 0) {
        const prio = this.priority[i];
        if (!prio.empty())
            return scheduler.threadFromSched(prio.front());

        i -= 1;
    }
    return null;
}

fn getTimeslice(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase) ?kernel.Time {
    _ = sched;
    _ = thread;
    return null;
}

fn setPriority(sched : *scheduler.Scheduler, thread : *kernel.ThreadBase, newPriority : anytype) void {
    const this = getFifo(sched.data);

    const priority = thread.sched.priority;

    const list = this.priority[newPriority];

    this.spinlock.lock();
    defer this.spinlock.unlock();

    this.priority[priority].remove(&thread.schedLink);

    if (priority < newPriority) {
        list.insertBack(&thread.schedLink);
    }
    else {
        list.insertFront(&thread.schedLink);
    }
}

