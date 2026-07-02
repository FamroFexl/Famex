const std = @import("std");

const kernel = @import("kernel");
const locks = kernel.util.locks;
const proc = kernel.pm.process;
const bin = kernel.util.binary;

const cpu = @import("arch").cpu;

val : std.atomic.Value(bool),

pub fn init(spinlock : *@This()) void {
    spinlock.val.store(false, .release);
}

pub fn tryLock(spinlock : *@This()) bool {
    kernel.irqSave();
    const locked = !spinlock.val.rmw(.Xchg, true, .acquire);
    if (locked) {
        locks.lockAdd(bin.castPtr(*anyopaque, spinlock));
    }
    else {
        kernel.irqRestore();
    }

    return locked;
}

pub fn lock(spinlock : *@This()) void {
    kernel.irqSave();

    if (!spinlock.val.rmw(.Xchg, true, .acquire)) {
        locks.lockAdd(bin.castPtr(*anyopaque, spinlock));
        return;
    }

    while (!spinlock.val.rmw(.Xchg, true, .acquire)) {
        cpu.spinWaitLoop();
    }

    locks.lockAdd(bin.castPtr(*anyopaque, spinlock));
}

pub fn unlock(spinlock : *@This()) void {
    spinlock.val.store(false, .release);

    locks.lockRemove(bin.castPtr(*anyopaque, spinlock));

    kernel.irqRestore();
}