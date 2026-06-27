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
        //semaphore.queue.push()
        semaphore.spinlock.unlock();
        //sleepThread()
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
    _ = node;

    semaphore.spinlock.unlock();
    //wakeThread()
}