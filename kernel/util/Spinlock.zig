const std = @import("std");

const locks = @import("kernel").util.locks;

const cpu = @import("arch").cpu;

val : std.atomic.Value(bool),

pub fn init(spinlock : *@This()) void {
    spinlock.val.store(false, .release);
}

pub fn tryLock(spinlock : *@This()) bool {
    const locked = !spinlock.val.rmw(.Xchg, true, .acquire);
    if (locked) {
        locks.lockAdd(@ptrCast(@constCast(&spinlock)));
    }

    return locked;
}

pub fn lock(spinlock : *@This()) void {
    // irq_save();
    if (tryLock(spinlock)) {
        return;
    }

    while (!spinlock.val.rmw(.Xchg, true, .acquire)) {
        cpu.spinWaitLoop();
    }

    locks.lockAdd(@ptrCast(@constCast(&spinlock)));
}

pub fn unlock(spinlock : *@This()) void {
    spinlock.val.store(false, .release);

    locks.lockRemove(@ptrCast(@constCast(&spinlock)));

    // irq_restore();
}