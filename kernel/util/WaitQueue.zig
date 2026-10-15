const std = @import("std");

const kernel = @import("kernel");

const ThreadQueue = kernel.util.data.QueueTyped(kernel.Thread, "sleepLink");

queue : ThreadQueue = undefined,
spinlock : kernel.Spinlock = .create(),

pub const Node = ThreadQueue.Node;

pub fn init(this : *@This()) void {
    this = .{};
    this.queue.init();
}

pub fn sleep(this : *@This(), thread : *kernel.Thread, spinlock : *kernel.Spinlock, state : kernel.Thread.State) void {
    kernel.lockHeld(spinlock);

    this.spinlock.lock();

    this.queue.push(thread);

    thread.spinlock.lock();
    thread.state = state;
    thread.spinlock.unlock();

    this.spinlock.unlock();

    spinlock.unlock();
    thread.sleep();
    spinlock.lock();
}

pub fn wakeNext(this : *@This()) bool {
    this.spinlock.lock();
    defer this.spinlock.unlock();

    if (this.queue.pop()) |thread| {
        thread.spinlock.lock();
        thread.state = .RUNNING;
        thread.spinlock.unlock();

        thread.wake();

        return true;
    }

    return false;
}

pub fn wakeAll(this : *@This()) void {
    this.spinlock.lock();

    while (this.queue.pop()) |thread| {
        thread.spinlock.lock();
        thread.state = .RUNNING;
        thread.spinlock.unlock();

        thread.wake();
    }

    this.spinlock.unlock();
}
