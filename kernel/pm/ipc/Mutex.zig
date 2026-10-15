const kernel = @import("kernel");
const Queue = kernel.util.data.Queue;

queue : kernel.util.WaitQueue = undefined,
locked : bool = false,
spinlock : kernel.util.Spinlock = .create(),

pub fn init(mutex : *@This()) void {
    mutex.* = .{};
    mutex.queue.init();
}

pub fn acquire(mutex : *@This()) void {
    mutex.spinlock.lock();

    const thread = kernel.cThread();

    while (mutex.locked) {
        mutex.queue.sleep(thread, &mutex.spinlock .UNINTERRUPTIBLE);
    }

    mutex.spinlock.unlock();
}

pub fn release(mutex : *@This()) void {
    mutex.spinlock.lock();

    mutex.locked = false;

    mutex.queue.wakeNext();

    mutex.spinlock.unlock();
}