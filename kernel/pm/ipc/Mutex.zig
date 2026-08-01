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
        const thread = kernel.cThread();
        mutex.queue.push(&thread.sleepLink);
        thread.spinlock.lock();
        thread.state = .UNINTERRUPTIBLE;
        thread.spinlock.unlock();
        thread.sleep();
    }
}

pub fn release(mutex : *@This()) void {
    mutex.spinlock.unlock();

    const node = mutex.queue.pop() orelse return;

    const thread : *kernel.Thread = @fieldParentPtr("sleepLink", node);

    thread.spinlock.lock();
    thread.state = .RUNNING;
    thread.spinlock.unlock();

    thread.wake();
}