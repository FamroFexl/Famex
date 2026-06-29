const std = @import("std");

const kernel = @import("kernel");

const Policy = enum {
    FIFO,       // First in-first out (FIFO) scheduling policy.
    SPORADIC,   // Sporadic server scheduling policy.
    RR,         // Round robin scheduling policy.
    OTHER,      // Primary and default scheduling policy (CFS)
};

const SchedData = struct {
    spinlock : kernel.util.Spinlock,
    sched : [std.meta.fields(Policy).len]*anyopaque,
    idle : *kernel.pm.process.ThreadBase,
    current : *kernel.pm.process.ThreadBase,
    flags : Flags,
    // kstacktop
    // nextTimer

    const Flags = packed struct {
        reschedule : bool,
    };
};

pub const schedData = kernel.pm.process.PerCpuStat(SchedData);

pub fn cThread() *kernel.pm.process.ThreadBase {
    return schedData.getLocal().current;
}

fn loadThread(new : *kernel.ThreadBase, state : *kernel.CpuState) void {
    const data = schedData.getLocal();

    data.current.context = state.*;

    data.current = new;
    // set kstack top
    state.* = new.context;

    kernel.mm.paging.switchPageTables(new.owner.addr_space.rootPt);
}