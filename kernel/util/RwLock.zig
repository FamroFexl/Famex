const std = @import("std");

const kernel = @import("kernel");
const cpu = @import("arch").cpu;

const WRITING_BIT : u32 = @intCast(kernel.bin.setBit(31));

val : std.atomic.Value(u32) = .{.raw = 0},

pub fn init(this : *@This()) void {
    this.val.raw = 0;
}

pub fn create() @This() {
    return .{.val = .init(0)};
}

pub fn readLock(this : *@This()) void {
    // Non-blocking for multiple readers
    while (true) {
        const lock = this.val.load(.acquire);

        // Spin if being written
        if (lock & WRITING_BIT == 1) {
            cpu.spinWaitLoop();
            continue;
        }

        // Change the value if it has not been written to
        if (this.val.cmpxchgWeak(lock, lock + 1, .acquire, .monotonic) == null) {
            break;
        }
    }
}

pub fn readUnlock(this : *@This()) void {
    _ = this.val.fetchSub(1, .release);
}

pub fn writeLock(this : *@This()) void {
    cpu.MemFence.full();

    while (true) {
        const lock = this.val.load(.acquire);

        // Spin if being written
        if (lock & WRITING_BIT == 1) {
            cpu.spinWaitLoop();
            continue;
        }

        // Try to set myself to the writer
        if (this.val.cmpxchgWeak(lock, lock & WRITING_BIT, .acquire, .monotonic) == null) {
            break;
        }
    }

    // Ensure no readers are active
    while (this.val.load(.acquire) > WRITING_BIT) {
        cpu.spinWaitLoop();
    }
}

pub fn writeUnlock(this : *@This()) void {
    // No readers are active, so we just have the writing bit to clear
    this.val.store(0, .release);
}