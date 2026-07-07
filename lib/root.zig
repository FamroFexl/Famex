pub const limine = @import("include/limine.zig");

pub const elf = @import("include/elf.zig");
pub const acpica = @import("acpica");

pub const linux = @import("linux");

pub const posix = @import("posix");

pub const cpuid_db = @import("include/cpuid_db.zig");

const std = @import("std");
const kernel = @import("kernel");
const cast = kernel.cast;

export fn __rcu_set(ptr : *?*anyopaque, val : ?*anyopaque) ?*anyopaque {
    return @atomicRmw(?*anyopaque, ptr, .Xchg, val, .release);
}

export fn __rcu_get(ptr : *?*anyopaque) ?*anyopaque {
    return @atomicLoad(?*anyopaque, ptr, .acquire);
}

export fn slub_alloc(pool : *anyopaque) *anyopaque {
    const slubPool = cast.toPtr(*kernel.SlubPool, pool);
    return slubPool.alloc();
}

export fn slub_free(addr : *anyopaque) void {
    kernel.SlubPool.free(addr);
}

export fn spin_lock(lock : *anyopaque) void {
    const spinlock = cast.toPtr(*kernel.Spinlock, lock);
    spinlock.lock();
}

export fn spin_unlock(lock : *anyopaque) void {
    const spinlock = cast.toPtr(*kernel.Spinlock, lock);
    spinlock.unlock();
}

export fn _spinlock_held(lock : *anyopaque) void {
    kernel.util.locks.lockHeld(lock);
}

extern fn xa_node_rcu_free(rcu_head : *kernel.RcuAsync) void;

fn slubFree(free : *kernel.RcuAsync) void {
    xa_node_rcu_free(free);
}

export fn slub_rcu_async_free(free : *anyopaque) void {
    const rcuFree = cast.toPtr(*kernel.RcuAsync, free);
    kernel.pm.ipc.rcu.asyncFree(rcuFree, slubFree);
}

export fn rcu_read_lock() void {
    kernel.pm.ipc.rcu.lock();
}

export fn rcu_read_unlock() void {
    kernel.pm.ipc.rcu.unlock();
}

export fn maple_pool_create(size : u64, alignment : u16) *anyopaque {
    return kernel.SlubPool.create(size, alignment, null);
}

fn clear(node : *anyopaque) void {
    kernel.memset(node, @sizeOf(linux.XArray.Node), 0);
}

export fn xa_pool_create(size : u64, alignment : u16) *anyopaque {
    return kernel.SlubPool.create(size, alignment, clear);
}