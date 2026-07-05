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
    .Debug => proc.PerCpuStat(LockData),
    else => void,
};

pub fn lockHeld(lock : *anyopaque) void {
    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.getLocal();
        for (0..data.cur_lock) |i| {
            if (data.held_locks[i] == lock)
                return;
        }
        log.panic("Lock was not held as required!\n", .{});
    }
}

pub fn lockAdd(lock : *anyopaque) void {
    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.getLocal();
        data.held_locks[data.cur_lock] = lock;
        data.cur_lock += 1;
    }
}

pub fn lockRemove(lock : *anyopaque) void {
    _ = lock;
    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.getLocal();
        data.cur_lock -= 1;
    }
}

pub fn setup() void {
    for (0..cpu.FEATURES.NUM_CPU_CORES) |i| {
        lock_data.getGlobal(i).cur_lock = 0;
    }
}