const std = @import("std");

const kernel = @import("kernel");
const Queue = kernel.util.data.Queue;

queue : kernel.util.data.Queue,
maxCount : u64,
curCount : u64,
spinlock : kernel.util.Spinlock,

pub fn init(semaphore : *@This(), maxCount : anytype) void {
    semaphore.queue.init();
    semaphore.spinlock.init();
    semaphore.maxCount = maxCount;
}

pub fn acquire(semaphore : *@This()) void {
    semaphore.spinlock.lock();

    if (semaphore.curCount == semaphore.maxCount) {
        semaphore.queue.push(&kernel.cThread().sleepLink);
        semaphore.spinlock.unlock();
        kernel.cThread().sleep();
    }
    else {
        semaphore.curCount += 1;
        semaphore.spinlock.unlock();
    }
}

pub fn release(semaphore : *@This()) void {
    semaphore.spinlock.lock();
    defer semaphore.spinlock.unlock();

    const node = semaphore.queue.pop() orelse {
        semaphore.curCount -= 1;
        semaphore.spinlock.unlock();
        return;
    };

    semaphore.spinlock.unlock();

    const thread : *kernel.Thread = @fieldParentPtr("sleepLink", node);
    thread.spinlock.lock();
    thread.state = .RUNNING;
    thread.spinlock.unlock();

    thread.wake();
}