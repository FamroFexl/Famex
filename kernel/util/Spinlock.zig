const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const locks = kernel.util.locks;
const proc = kernel.pm.process;
const bin = kernel.util.binary;

const cpu = @import("arch").cpu;

val : std.atomic.Value(bool),

pub fn init(spinlock : *@This()) void {
    spinlock.val.store(false, .unordered);
}

pub fn create() @This() {
    return .{.val = .init(false)};
}

pub fn tryLock(spinlock : *@This()) bool {
    kernel.irqSave();
    _ = spinlock.val.cmpxchgStrong(false, true, .acquire, .monotonic) orelse {
        locks.lockAdd(spinlock);
        return true;
    };

    kernel.irqRestore();
    return false;
}

pub fn lock(spinlock : *@This()) void {
    kernel.irqSave();

    _ = spinlock.val.cmpxchgStrong(false, true, .acquire, .monotonic) orelse {
        locks.lockAdd(spinlock);
        return;
    };

    while (spinlock.val.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
        cpu.spinWaitLoop();
    }

    locks.lockAdd(spinlock);
}

pub fn unlock(spinlock : *@This()) void { kernel.noIrq();
    spinlock.val.store(false, .release);

    locks.lockRemove(spinlock);

    kernel.irqRestore();
}