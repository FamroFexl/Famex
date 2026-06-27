const kernel = @import("kernel");
const Queue = kernel.util.data.Queue;

queue : Queue,
spinlock : kernel.util.Spinlock,

pub fn init(mutex : *@This()) void {
    mutex.queue.init();
    mutex.spinlock.init();
}

pub fn acquire(mutex : *@This()) void {
    const lock = mutex.spinlock.tryLock();

    if (!lock) {
        //mutex.queue.push()
        //sleepThread()
    }
}

pub fn release(mutex : *@This()) void {
    mutex.spinlock.unlock();

    const node = mutex.queue.pop() orelse return;
    _ = node;

    //wakeThread()
}