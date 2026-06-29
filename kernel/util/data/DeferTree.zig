//! Deferred action cpu synchronization tree, useful for things like RCU free

const CpuTree = @import("CpuTree.zig");

const kernel = @import("kernel");
const proc = kernel.pm.process;
const mem = kernel.mm.memory;
const util = kernel.util;

const cpu = @import("arch").cpu;

cpuTree : *CpuTree,
stacks : proc.PerCpuDyn([3]util.data.Stack),

pub const State = struct {
    node : util.data.Stack.Node,
    callback : *const fn (*State) void,
};

pub fn create(mask : proc.CpuMask) *@This() {
    const tree = mem.pmalloc(@This());
    tree.stacks.alloc();

    for (0..cpu.FEATURES.NUM_CPU_CORES) |i| {
        var stack = tree.stacks.getGlobal(i);
        for (0..3) |j| {
            stack[j].init();
        }
    }

    tree.cpuTree = CpuTree.create(mask, null);

    return tree;
}

pub fn free(tree : *@This()) void {
    tree.cpuTree.free();

    tree.stacks.free();

    mem.pfree(@This(), tree);
}

/// Wait until the next grace period
pub fn wait(tree : *@This()) void {
    const oldGp = tree.cpuTree.getPeriod();
    while (oldGp + 2 > tree.cpuTree.getPeriod()) {
        cpu.spinWaitLoop();
    }
}

// push 2, pop 0   (2 + 1) % 3 = 0
// push 0, pop 1    (0 + 1) % 3 = 1
// push 1, pop 2    (1 + 1) % 3 = 2

// push == period % 3
pub fn push(tree : *@This(), state : *State, callback : fn (*State) void) void {
    state.callback = callback;
    const stack = tree.cpuTree.getPeriod() % 3;

    proc.preemptSave();
    defer proc.preemptRestore();

    var stacks = tree.stacks.getLocal().*;
    stacks[stack].push(&state.node);
}

// pop == (period + 1) % 3
fn pop(tree : *@This()) ?*State {
    const stack = (tree.cpuTree.getPeriod + 1) % 3;
    var node : util.data.Stack.Node = undefined;

    proc.preemptSave();
    defer proc.preemptRestore();

    const stacks = tree.stacks.getLocal().*;
    node = stacks[stack].pop() orelse return null;

    return @fieldParentPtr("node", node);
}

pub fn report(tree : *@This(), cpu_num : anytype) void {
    const reported = tree.cpuTree.report(cpu_num);

    if (!reported) {
        // Free all nodes from 2 periods ago
        while (true) {
            const state = pop(tree) orelse break;

            state.callback();
        }
    }
}

pub fn disable(tree : *@This(), cpu_num : anytype) void {
    tree.cpuTree.disable(cpu_num);
}

pub fn enable(tree : *@This(), cpu_num : anytype) void {
    tree.cpuTree.enable(cpu_num);
}

