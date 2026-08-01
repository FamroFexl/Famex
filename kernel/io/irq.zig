const std = @import("std");

const kernel = @import("kernel");
const DeferTree = kernel.util.data.DeferTree;
const process = kernel.pm.process;
const sched = kernel.pm.sched.scheduler;
const rcu = kernel.pm.ipc.rcu;

const arch = @import("arch");
const irq = arch.irq;
const cpu = arch.cpu;

const exception = @import("exception.zig");

pub const IrqType = enum {
    DEVICE,         // Device IRQ
    EXCEPTION,      // CPU exception
    LOCAL_TIMER,    // Local timer
    IPI,            // Inter-Processor Interrupt
    SPURIOUS        // Spurious (undefined) Interrupt
};

pub const IrqData = struct {
    irqNum : u64,
    data : ?*anyopaque,
};

/// Tracks time spent in IRQs
const inIrqTime = kernel.PerCpuStat(u64, opaque {});

/// Depth of IRQ disable requests
pub const irqSaveDepth = kernel.PerCpuStat(*u64, opaque {});

/// Depth of IRQ nesting we are in
const irqNestDepth = kernel.PerCpuStat(u8, opaque {});

pub fn irqSave() void {
    cpu.irqDisable();

    irqSaveDepth.getLocal().*.* += 1;
}

pub fn irqRestore() void { noIrq();
    const depth = irqSaveDepth.getLocal().*;
    depth.* -= 1;

    if (depth.* == 0) {
        cpu.irqEnable();
    }
}

pub fn inIrq() bool {
    return irqNestDepth.getLocal().* > 0;
}

/// No IRQ allowed
pub fn noIrq() void {
    if (cpu.irqEnabled())
        @panic("IRQ was enabled in a disabled section!");
}

/// IRQ must be saved in this section
pub fn irqSaved() void {
    if (irqSaveDepth.getLocal().*.* == 0)
        @panic("IRQ wasn't saved before!");
}

pub const SmpCall = struct {
    data : CallInfo,
    state : DeferTree.State,

    // These may be unnecessary
    cpuId : u8,             // CPU ID of the sending core
    mask : kernel.CpuMask,  // Mask of all Cpus that received this request
    curGp : u64,            // Current grace period for synchronization

    /// Used for non-contentious deferred frees of SmpCalls
    pub var TREE : *DeferTree = undefined;

    /// Queue of per-cpu pending SMP requests
    const queue = kernel.PerCpuStat(kernel.util.data.MpscQueue, opaque {});

    pub const CallInfo = struct {
        func : *const fn(*const @This()) void,
        args : [6]usize,
    };

    /// Main function to free the SmpCall and its Links
    pub fn free(this : *const DeferTree.State) void {
        const request : *SmpCall = @fieldParentPtr("state", @constCast(this));
        kernel.pfreeBytes(request);
    }

    const Link = struct {
        link : kernel.util.data.MpscQueue.Node,
        payload : *SmpCall,
    };

    /// SMP call for cpus in mask. Async determines if the caller waits until all CPUs have completed.
    /// NOTE: freeFn must free the SmpCall. If freeFn is null, it will just free itself.
    pub fn create(mask : kernel.CpuMask, async : bool, freeFn : ?*const fn (*DeferTree.State) void, data : SmpCall.CallInfo) void {
        if (mask == 0) return;

        var modMask = mask & ~kernel.bin.setBit(kernel.getCpuId());

        // Only local CPU was in mask
        if (modMask == 0) {
            data.func(&data);
            return;
        }

        const localCall = modMask != mask;

        const request = kernel.cast.toPtr(*SmpCall, kernel.pmallocBytes(@sizeOf(SmpCall) + @popCount(mask) * @sizeOf(Link)));
        // Links are bundled with the smp request so all can be freed and allocated in a single call
        const links = kernel.bin.getFlexArray(SmpCall, Link, request);

        const freeFunc = freeFn orelse free;

        request.data = data;
        request.cpuId = kernel.getCpuId();
        request.mask = mask;

        while (modMask > 0) {
            const i = @ctz(modMask);
            modMask &= modMask - 1;

            const link = &links[i];
            link.payload = request;

            // Add to remote cpu's queue
            queue.getGlobal(i).push(&link.link);

            // Send a request to the target CPU
            irq.notifyCpu(i);
        }

        if (localCall)
            data.func(&data);

        if (async) {
            TREE.push(&request.state, freeFunc);
        }
        else {
            TREE.wait();
            freeFunc(&request.state);
        }
    }

    /// Handle all queued SMP calls
    pub fn handler() void {
        const local = queue.getLocal();

        while (local.pop()) |node| {
            const link : *Link = @fieldParentPtr("link", node);
            link.payload.data.func(&link.payload.data);
        }

        // Report that we have completed an smp handling cycle so SmpCalls and Links can be defer freed
        TREE.report(kernel.getCpuId());
    }
};

fn deviceHandler(irqNum : u64, state : *cpu.CpuState) void {
    _ = irqNum;
    _ = state;
}

/// Operations to perform on nested interrupts
fn nestedHandler(data : *const IrqData, state : *cpu.CpuState) void {
    switch (irq.getIrqType(data.irqNum)) {
        .LOCAL_TIMER => kernel.pm.time.TimerEvent.handler(),
        .IPI => SmpCall.handler(),
        .EXCEPTION => exception.handler(data.irqNum, @ptrCast(@alignCast(data.data)), state),
        .DEVICE => deviceHandler(data.irqNum, state),
        .SPURIOUS => return,
    }
}

/// Operations to perform on a first-level interrupt
fn threadHandler(data : *const IrqData, state : *cpu.CpuState) void { kernel.util.locks.noLocksHeld();
    if (!sched.cThread().context.inKmode()) {
        rcu.exitEqs();
        process.addUtime();
    }
    else {
        process.addKtime();
    }

    const schedData = sched.schedData.getLocal();

    // Operations in the IRQ may use preemptSave and preemptRestore,
    // and we don't want them triggering any processes if preemption
    // becomes enabled. Preemption is effectively disabled for the
    // duration of an interrupt.
    schedData.current.preemptDepth += 1;

    nestedHandler(data, state);

    schedData.current.preemptDepth -= 1;

    if (schedData.flags.reschedule and sched.cThread().preemptDepth == 0) {
        sched.schedule(state);
        rcu.reportQs();
    }

    kernel.pm.signal.sigHandle(state);

    if (!sched.cThread().context.inKmode()) {
        rcu.enterEqs();
    }

    // Add time in irq
    inIrqTime.getLocal().* += process.startTimeReset();
}

pub fn handler(data : *const IrqData, state : *cpu.CpuState) void { noIrq();
    const depth = irqNestDepth.getLocal();

    depth.* += 1;

    // Interrupts are NEVER enabled in IRQ context implicitly
    // so irqSave and irqRestore should never enable them.
    var inIrqSaveDepth : u64 = 1;
    irqSaveDepth.getLocal().* = &inIrqSaveDepth;

    if (depth.* == 1) {
        threadHandler(data, state);

        irqSaveDepth.getLocal().* = &sched.cThread().irqSaveDepth;
    }
    else {
        nestedHandler(data, state);
    }

    depth.* -= 1;
}

pub fn setup() void {
    SmpCall.TREE = DeferTree.create(kernel.cpuMaskFull());

    for (0..cpu.FEATURES.NUM_CPU_CORES) |i| {
        SmpCall.queue.getGlobal(i).init();
        inIrqTime.getGlobal(i).* = 0;
        irqNestDepth.getGlobal(i).* = 0;
    }

    exception.setup();
}