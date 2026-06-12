const builtin = @import("builtin");
const kernel = @import("kernel");
const proc = kernel.proc;
const log = kernel.util.log;

const LockData = struct {
    held_locks : [64]*anyopaque,
    cur_lock : u64,
};

const lock_data = switch (builtin.mode) {
    .Debug => proc.PerCpuStat(LockData),
    else => void,
};

pub fn lock_held(lock : *anyopaque) void {
    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.get_local();
        for (0..data.cur_lock) |i| {
            if (data.held_locks[i] == lock)
                return;
        }
        log.panic("Lock was not held as required!\n", .{});
    }
}

pub fn lock_add(lock : *anyopaque) void {
    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.get_local();
        data.held_locks[data.cur_lock] = lock;
        data.cur_lock += 1;
    }
}

pub fn lock_remove(lock : *anyopaque) void {
    _ = lock;
    if (builtin.mode == .Debug) {
        const data : *LockData  = lock_data.get_local();
        data.cur_lock -= 1;
    }
}