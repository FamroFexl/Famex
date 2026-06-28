const std = @import("std");

const kernel = @import("kernel");
const proc = kernel.pm.process;
const DeferTree = kernel.util.data.DeferTree;

const cpu = @import("arch").cpu;

pub const RcuFree = DeferTree.State;

var TREE : *DeferTree = undefined;

pub fn RcuPtr(comptime T : type) type {
    return struct {
        ptr : std.atomic.Value(*T),

        /// Get the RCU ptr
        pub fn get(self : *@This()) *T {
            return self.ptr.load(.acquire);
        }

        /// Set the RCU to ptr and return the old value
        pub fn set(self : *@This(), ptr : ?*T) *T {
            return self.ptr.swap(ptr, if (ptr == null) .unordered else .release);
        }

        /// Asynchronous free using a free struct
        pub fn async(free : *RcuFree, callback : fn (*RcuFree) void) void {
            TREE.push(free, callback);
        }

        /// Synchronous wait until the next grace period
        pub fn sync() void {
            TREE.wait();
        }

        /// RCU read lock
        pub fn lock() void {
            proc.preemptSave();
        }

        /// RCU read lock and RCU ptr return
        pub fn lockAndGet(self : *@This()) *T {
            lock();
            return get(self);
        }

        /// RCU read unlock
        pub fn unlock() void {
            proc.preemptRestore();
        }
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
    TREE = DeferTree.create(proc.cpuMaskFull());
}