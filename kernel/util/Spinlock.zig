const std = @import("std");

const kernel = @import("kernel");
const locks = kernel.util.locks;
const proc = kernel.pm.process;
const bin = kernel.util.binary;

const cpu = @import("arch").cpu;

val : std.atomic.Value(bool),

pub fn init(spinlock : *@This()) void {
    spinlock.val.store(false, .unordered);
}

pub fn tryLock(spinlock : *@This()) bool {
    kernel.irqSave();
    _ = spinlock.val.cmpxchgStrong(false, true, .acquire, .monotonic) orelse {
        locks.lockAdd(bin.castPtr(*anyopaque, spinlock));
        return true;
    };

    kernel.irqRestore();
    return false;
}

pub fn lock(spinlock : *@This()) void {
    kernel.irqSave();

    _ = spinlock.val.cmpxchgStrong(false, true, .acquire, .monotonic) orelse {
        locks.lockAdd(bin.castPtr(*anyopaque, spinlock));
        return;
    };

    while (spinlock.val.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
        cpu.spinWaitLoop();
    }

    locks.lockAdd(bin.castPtr(*anyopaque, spinlock));
}

pub fn unlock(spinlock : *@This()) void {
    std.debug.assert(!kernel.irqEnabled());

    spinlock.val.store(false, .release);

    locks.lockRemove(bin.castPtr(*anyopaque, spinlock));

    kernel.irqRestore();
}