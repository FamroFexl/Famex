const std = @import("std");

const kernel = @import("kernel");
const Queue = kernel.util.data.Queue;

queue : kernel.util.WaitQueue = undefined,
maxCount : u64 = undefined,
curCount : u64 = 0,
spinlock : kernel.util.Spinlock = .create(),

pub fn init(semaphore : *@This(), maxCount : anytype) void {
    semaphore.* = .{};
    semaphore.queue.init();
    semaphore.maxCount = maxCount;
}

pub fn acquire(semaphore : *@This()) void {
    semaphore.spinlock.lock();

    const thread = kernel.cThread();

    while (semaphore.curCount == semaphore.maxCount) {
        semaphore.queue.sleep(thread, &semaphore.spinlock, .UNINTERRUPTIBLE);
    }

    semaphore.curCount += 1;

    semaphore.spinlock.unlock();
}

pub fn release(semaphore : *@This()) void {
    semaphore.spinlock.lock();
    defer semaphore.spinlock.unlock();

    if (semaphore.queue.wakeNext()) {
        semaphore.curCount -= 1;

        return;
    }

    semaphore.spinlock.unlock();
}