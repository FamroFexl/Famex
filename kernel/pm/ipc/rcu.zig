//! Read->Copy->Update mechanism for seamless pointer swapping and object freeing

const std = @import("std");

const kernel = @import("kernel");
const proc = kernel.pm.process;
const DeferTree = kernel.util.data.DeferTree;

const cpu = @import("arch").cpu;

const rcu = @This();

var TREE : *DeferTree = undefined;

/// Synchronous wait until the next grace period
pub fn sync() void {
    TREE.wait();
}

/// RCU read lock
pub fn lock() void {
    kernel.ThreadBase.preemptSave(kernel.cThread());
}

/// RCU read unlock
pub fn unlock() void {
    kernel.ThreadBase.preemptRestore(kernel.cThread());
}

pub fn asyncFree(state : *RcuAsync, callback : fn (*RcuAsync) void) void {
    TREE.push(state, callback);
}

pub fn syncFree(state : *RcuAsync, callback : fn (*RcuAsync) void) void {
    rcu.sync();
    callback(state);
}

fn pmallocFree(comptime T : type, addr : *anyopaque) void {
    kernel.pfree(T, addr);
}

fn vmallocFree(comptime T : type, addr : *anyopaque) void {
    kernel.vfree(T, addr);
}

fn slubAllocFree(ptr : *anyopaque) void {
    kernel.SlubPool.free(ptr);
}

fn buddyAllocFree(ptr : *anyopaque) void {
    kernel.freePage(kernel.Vaddr.asVirt(@intFromPtr(ptr)).toPhys());
}

const AllocType = enum {
    PMALLOC,
    VMALLOC,
    SLUB_ALLOC,
    BUDDY_ALLOC,
};

pub const RcuAsync = DeferTree.State;

fn RcuFree(comptime T : type, comptime alloc : AllocType) type {
    return struct {
        pub var val : *T = undefined;

        fn getName() []const u8 {
            return comptime blk: {
                for (@typeInfo(T).@"struct".fields) |f| {
                    if (f.type == RcuAsync) break :blk f.name;
                }
                unreachable;
            };
        }

        fn getState() *RcuAsync {
            return &@field(val, getName());
        }

        fn free(ptr : *anyopaque) void {
            switch (alloc) {
                .PMALLOC => pmallocFree(T, ptr),
                .VMALLOC => vmallocFree(T, ptr),
                .BUDDY_ALLOC => buddyAllocFree(ptr),
                .SLUB_ALLOC => slubAllocFree(ptr),
            }
        }

        /// Free after sync
        pub fn syncFree() void {
            rcu.sync();
            free(val);
        }

        pub fn get() *T {
            return val;
        }

        fn freeAsync(state : *RcuAsync) void {
            free(@fieldParentPtr(getName(), state));
        }

        /// Async free
        pub fn asyncFree() void {
            TREE.push(getState(), freeAsync);
        }

        /// Async free with other
        pub fn asyncFreeOther(callback : fn (*RcuAsync) void) void {
            TREE.push(getState(), callback);
        }
    };
}

pub fn RcuPtr(comptime T : type, comptime alloc : AllocType) type {
    return struct {
        ptr : std.atomic.Value(*T),

        /// Get the RCU ptr
        pub fn get(this : *@This()) *T {
            return this.ptr.load(.acquire);
        }

        /// Set the RCU to ptr and return the old value
        pub fn swap(this : *@This(), ptr : *T) RcuFree {
            const old = this.ptr.swap(ptr, if (ptr == null) .unordered else .release);
            const free = RcuFree(T, alloc);
            free.val = old;
            return free;
        }

        /// RCU read lock and RCU ptr return
        pub fn lockAndGet(this : *@This()) *T {
            rcu.lock();
            return get(this);
        }

        pub const lock = rcu.lock;

        pub const unlock = rcu.unlock;
    };
}

/// Report a quiescent state has passed for this cpu
pub fn reportQs() void {
    TREE.report(cpu.getCpuId());
}

/// CPU enters an extended quiescent state (no longer influences grace period)
pub fn enterEqs() void {
    TREE.disable(cpu.getCpuId());
}

/// CPU exits an extended quiescent state (now influences grace period)
pub fn exitEqs() void {
    TREE.enable(cpu.getCpuId());
}

pub fn setup() void {
    kernel.print("mm: Setting up Read-Copy-Update\n", .{});

    TREE = DeferTree.create(proc.cpuMaskFull());
}