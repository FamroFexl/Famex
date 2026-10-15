const builtin = @import("builtin");
const kernel = @import("kernel");
const proc = kernel.pm.process;
const log = kernel.util.log;

const cpu = @import("arch").cpu;

const LockData = struct {
    held_locks : [64]*anyopaque,
    cur_lock : u64,
};

const lock_data = switch (builtin.mode) {
    .Debug => proc.PerCpuStat(LockData, opaque {}),
    else => void,
};

/// Verifies the lock is held by this cpu
pub fn lockHeld(lock : *anyopaque) void {
    kernel.irqSave();
    defer kernel.irqRestore();

    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.getLocal();
        for (0..data.cur_lock) |i| {
            if (data.held_locks[i] == lock)
                return;
        }
        @panic("Lock was not held!");
    }
}

pub fn lockTryAdd(lock : *anyopaque) void {
    kernel.irqSave();
    defer kernel.irqRestore();

    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.getLocal();

        for (0..data.cur_lock) |i| {
            if (data.held_locks[i] == lock)
                @panic("Lock was already held!");
        }
    }
}

/// Adds a lock to the list
pub fn lockAdd(lock : *anyopaque) void {
    kernel.irqSave();
    defer kernel.irqRestore();

    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.getLocal();

        data.held_locks[data.cur_lock] = lock;
        data.cur_lock += 1;
    }
}

/// Removes the last lock
pub fn lockRemove(lock : *anyopaque) void {
    _ = lock;
    kernel.irqSave();
    defer kernel.irqRestore();

    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.getLocal();
        if (data.cur_lock == 0)
            @panic("Lock was already freed!");
        // This prevents interlocking (lock A, lock B, unlock A, unlock B),
        // and only nested locking (lock A, lock B, unlock B, unlock A)
        //if (data.held_locks[data.cur_lock - 1] != lock) {
            //if (data.held_locks[data.cur_lock - 2] == lock)
            //    @panic("Last lock wasn't freed!");
            //for (1..data.cur_lock) |i| {
            //    if (data.held_locks[data.cur_lock - i] == lock)
            //        kernel.util.log.panic("{} locks weren't freed before this!", .{i});
            //}
            //@panic("Lock was already freed!");
        //}
        data.cur_lock -= 1;
    }
}

/// Verifies no locks are held
pub fn noLocksHeld() void {
    kernel.irqSave();
    defer kernel.irqRestore();

    if (builtin.mode == .Debug and lock_data.getLocal().cur_lock != 0) {
        @panic("Locks were held!");
    }
}

pub fn setup() void {
    if (builtin.mode == .Debug) {
        for (0..cpu.FEATURES.NUM_CPU_CORES) |i| {
            lock_data.getGlobal(i).cur_lock = 0;
        }
    }
}