const std = @import("std");
const Op = std.builtin.AtomicRmwOp;
const Order = std.builtin.AtomicOrder;

const locks = @import("kernel").util.locks;

const cpu = @import("arch").cpu;

val : bool,

pub fn init(spinlock : *@This()) void {
    @atomicStore(bool, &spinlock.val, false, Order.release);
}

pub fn try_lock(spinlock : *@This()) bool {
    const locked = !@atomicRmw(bool, &spinlock.val, Op.Xchg, true, Order.acquire);
    if (locked) {
        locks.lock_add(&spinlock);
    }
}

pub fn lock(spinlock : *@This()) void {
    // irq_save();
    if (try_lock(spinlock)) {
        return;
    }

    while (!@atomicRmw(bool, &spinlock.val, Op.Xchg, true, Order.acquire)) {
        cpu.spin_wait_loop();
    }

    locks.lock_add(&spinlock);
}

pub fn unlock(spinlock : *@This()) void {
    @atomicStore(bool, &spinlock.val, false, Order.release);

    locks.lock_remove(&spinlock);

    // irq_restore();
}