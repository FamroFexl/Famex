const std = @import("std");

const kernel = @import("kernel");
const DeferTree = kernel.util.data.DeferTree;
const process = kernel.pm.process;
const sched = kernel.pm.sched.scheduler;
const rcu = kernel.pm.ipc.rcu;

const exception = @import("exception.zig");

const arch = @import("arch");
const irq = arch.irq;
const cpu = arch.cpu;

pub const IrqType = enum {
    DEVICE,         // Device IRQ
    EXCEPTION,      // CPU exception
    LOCAL_TIMER,    // Local timer
    IPI,            // Inter-Processor Interrupt
    SPURIOUS        // Spurious (undefined) Interrupt
};

pub const IrqData = struct {
    irqNum : u64,
};

/// Tracks time spent in IRQs
const inIrqTime = kernel.PerCpuStat(u64);

/// Depth of IRQ nesting we are in
const nestDepth = kernel.PerCpuStat(u8);

/// Depth of IRQ disable requests
pub const irqSaveDepth = kernel.PerCpuStat(u64);

pub fn irqSave() void {
    cpu.irqDisable();

    irqSaveDepth.getLocal().* += 1;
}

pub fn irqRestore() void {
    std.debug.assert(!cpu.irqEnabled());

    const depth = irqSaveDepth.getLocal();
    depth.* -= 1;

    if (depth.* == 0) {
        cpu.irqEnable();
    }
}

pub fn inIrq() bool {
    return IrqData.nestDepth.getLocal().* > 0;
}

pub const SmpRequest = struct {
    data : CallInfo,
    state : DeferTree.State,

    // These may be unnecessary
    cpuId : u8,             // CPU ID of the sending core
    mask : kernel.CpuMask,  // Mask of all Cpus that received this request

    /// Used for non-contentious deferred frees of SmpRequest and SmpLink types
    pub const tree : *DeferTree = undefined;

    /// Queue of per-cpu pending SMP requests
    const queue = kernel.PerCpuStat(kernel.util.data.MpscQueue);

    const CallInfo = struct {
        func : *const fn(*@This()) void,
        args : [6]usize = std.mem.zeroes([6]usize),
    };

    pub fn free(this : *@This()) void {
        kernel.pfree(@This(), this);
    }

    const Link = struct {
        link : kernel.util.data.MpscQueue.Node,
        payload : *SmpRequest,
        free : DeferTree.State,
    };

    fn linkFree(state : *DeferTree.State) void {
        kernel.pfree(Link, @fieldParentPtr("state", state));
    }

    /// SMP call for cpus in mask. Async determines if the caller waits until all CPUs have completed.
    /// NOTE: The free function must free the SmpRequest.
    pub fn create(mask : kernel.CpuMask, async : bool, data : SmpRequest.CallInfo, freeFn : *const fn (*DeferTree.State) void) void {
        const request = kernel.pmalloc(SmpRequest);

        request.data = data;
        request.cpuId = kernel.getCpuId();
        request.mask = mask;

        var localCall : bool = false;

        var modMask = mask;
        while (modMask > 0) {
            const i = @ctz(modMask);
            modMask &= modMask - 1;

            if (i == request.cpuId) {
                localCall = true;
                continue;
            }

            const link = kernel.pmalloc(Link);
            link.payload = request;

            // Automatically free link nodes when the request is freed
            tree.push(&link.free, linkFree);

            // Add to remote cpu's queue
            queue.getLocal().push(&link.link);

            // Send a request to the target CPU
            irq.notifyCpu(i);
        }

        if (localCall)
            data.func();

        if (async) {
            tree.push(&request.state, freeFn);
        }
        else {
            tree.wait();
            freeFn(&request.state);
        }
    }

    /// Handle all queued SMP calls
    pub fn handler() void {
        const local = queue.getLocal();

        while (true) {
            const node = local.pop();

            if (node) |n| {
                const link : *Link = @fieldParentPtr("link", n);
                link.payload.data.func();
            }
            else {
                break;
            }
        }

        // Report that we have completed a smp handling cycle so SmpRequests and Links can be defer freed
        tree.report(kernel.getCpuId());
    }
};

fn deviceHandler(irqNum : u64, state : *cpu.CpuState) void {
    _ = irqNum;
    _ = state;
}

/// Operations to perform on nested interrupts
fn nestedHandler(data : *IrqData, state : *cpu.CpuState) void {
    switch (irq.getIrqType(data.irqNum)) {
        .LOCAL_TIMER => kernel.pm.time.TimerEvent.handler(),
        .IPI => SmpRequest.handler(),
        .EXCEPTION => exception.handler(data),
        .DEVICE => deviceHandler(data.irqNum, state),
        .SPURIOUS => return,
    }
}

/// Operations to perform on a first-level interrupt
fn threadHandler(data : *IrqData, state : *cpu.CpuState) void {
    if (!process.inKmode(sched.cThread().context)) {
        rcu.exitEqs();
        process.addUtime();
    }
    else {
        process.addKtime();
    }

    const schedData = sched.schedData.getLocal();
    const depth = irqSaveDepth.getLocal();

    // Interrupts are NEVER enabled in IRQ context implicitly
    // so irqSave and irqRestore should never enable them.
    depth.* += 1;

    // Operations in the IRQ may use preemptSave and preemptRestore,
    // and we don't want them triggering any processes if preemption
    // becomes enabled. Preemption is effectively disabled for the
    // duration of an interrupt.
    schedData.current.preemptDepth += 1;

    nestedHandler(data, state);

    schedData.current.preemptDepth -= 1;

    if (schedData.flags.reschedule and sched.cThread().preemptDepth == 0) {
        // schedule(state);
        rcu.reportQs();
    }

    // TODO Check for signals with the current thread

    if (!process.inKmode(sched.cThread().context)) {
        rcu.enterEqs();
    }

    // All threads resume with interrupts enabled,
    // (except for threads that did a switch_thread(),
    // and they handle their own reentry)
    depth.* = 0;

    // Add time in irq
    inIrqTime.getLocal().* += process.startTimeReset();
}

pub fn handler(data : *IrqData, state : *cpu.CpuState) void {
    std.debug.assert(!cpu.irqEnabled());

    const depth = nestDepth.getLocal();

    depth.* += 1;

    if (depth.* == 1) {
        threadHandler(data, state);
    }
    else {
        nestedHandler(data, state);
    }

    depth.* -= 1;
}

pub fn setup() void {
    SmpRequest.tree = DeferTree.create(kernel.cpuMaskFull());

    for (0..cpu.FEATURES.NUM_CPU_CORES) |i| {
        SmpRequest.queue.getGlobal(i).init();
        inIrqTime.getGlobal(i).* = 0;
        nestDepth.getGlobal(i).* = 0;
    }
}