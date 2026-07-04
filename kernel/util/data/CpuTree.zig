//! Cache-friendly cpu synchronization mechanism

const cpu = @import("arch").cpu;

const kernel = @import("kernel");
const proc = kernel.pm.process;
const slub = kernel.mm.slubAlloc;
const mem = kernel.mm.memory;
const log = kernel.util.log;
const bin = kernel.util.binary;
const Spinlock = kernel.util.Spinlock;
const locks = kernel.util.locks;
const std = @import("std");

sync : *const fn (u64) void,
mask : proc.CpuMask,
curPeriod : std.atomic.Value(u64),
maxContention : u8,

fn syncNull(_ : u64) void {}

fn leafNodes(this : *@This()) [*]*Node {
    return bin.getFlexArray(@This(), *Node, this);
}

const Node = struct {
    parent : ?*@This(),
    spinlock : kernel.util.Spinlock,
    curPeriod : u64,
    target : proc.CpuMask, // Target of reported CPUs
    cur : proc.CpuMask,    // Current mask of reported CPUs
    init : proc.CpuMask,   // Mask to initialize with
};

fn getNthSetCpu(mask : proc.CpuMask, cpu_num : anytype) u8 {
    var new_mask = mask;
    var num = cpu_num;
    while (num > 0) : (num -= 1) {
        new_mask &= new_mask - 1;
    }

    return @ctz(mask);
}

/// Debug node printing for balancing node branching
const DEBUG_NODE = false;

fn createNodeRec(tree : *@This(), parent : ?*Node, count : u8, curNode : *u8, curMask : proc.CpuMask, depth : u8) void {
    const node = bin.castPtr(*Node, slub.cacheline_pool.alloc());
    node.parent = parent;
    node.spinlock.init();
    node.curPeriod = 0;
    node.target = curMask;
    node.cur = 0;
    node.init = 0;

    const ref = curMask;
    var new_count = count;

    var nodePrint = false;
    var nodeCount : u8 = 0;

    const chunks = bin.alignUpNum(count, tree.maxContention) / tree.maxContention;
    for (0..tree.maxContention) |i| {
        if (new_count <= tree.maxContention - i) {
            if (DEBUG_NODE) {
                log.printChar(' ', depth * 4);
                log.print("leaf {}", .{new_count});
                if (nodePrint) {
                    log.print(" under {}\n", .{nodeCount});
                }
                else {
                    log.print(" (mask {b:64}\n", .{curMask});
                }
            }
            // Add leaf node
            tree.leafNodes()[curNode.*] = node;
            curNode.* += 1;
            break;
        }

        if (DEBUG_NODE and !nodePrint) {
            nodePrint = true;
            nodeCount = new_count;
            log.printChar(' ', depth * 4);
            log.print("node {} (mask {b:64})\n", .{new_count, curMask});
        }

        var next : u8 = @intCast(bin.alignUpNum(chunks, tree.maxContention));
        if (next > new_count) next = new_count;
        const cpus : proc.CpuMask = bin.setBits(getNthSetCpu(ref, next - 1) + 1);
        const newMask = ref & cpus;

        createNodeRec(tree, node, next, curNode, newMask, depth + 1);

        new_count -= next;
        if (new_count == 0) break;
    }
}

fn delNodeRec(tree : *@This(), nodeList : [*]*Node, numNodes : u8) void {
    var parentList : [std.math.maxInt(u8)]*Node = undefined;
    var nodes : u8 = 0;

    var curParent : ?*Node = null;
    for (0..numNodes) |i| {
        const node = nodeList[i];
        const parent = node.parent;

        slub.cacheline_pool.free(node);

        // Only the root node doesn't have a parent, so we only need to free 1
        if (parent == null) return;

        if (curParent == null or parent != curParent) {
            curParent = parent;
            nodes += 1;
            parentList[nodes] = curParent;
        }
    }

    delNodeRec(tree, parentList, numNodes);
}

// Node lock must be obtained by caller
fn propagate(tree : *@This(), node : *Node, mask : proc.CpuMask) void {
    locks.lockHeld(&node.spinlock);

    node.cur |= mask;

    if (node.cur == node.target) {
        node.cur = node.init;
        node.curPeriod = tree.curPeriod.load(.acquire);

        node.spinlock.unlock();

        if (node.parent) |_| {
            node.parent.?.spinlock.lock();
            propagate(tree, node.parent.?, node.target);
        }
        else {
            _ = tree.curPeriod.fetchAdd(1, .release);
            tree.sync(node.curPeriod);
        }
    }
    else {
        node.spinlock.unlock();
    }
}

pub fn getPeriod(tree : *@This()) u64 {
    return tree.curPeriod.load(.acquire);
}

fn getNode(tree : *@This(), cpu_num : u8) ?*Node {
    if (tree.mask & bin.setBit(cpu_num) == 0) return null;

    const node = @popCount(tree.mask & bin.setBits(cpu_num)) / tree.maxContention;
    return tree.leafNodes()[node];
}

/// Create a Cpu tree
pub fn create(mask : proc.CpuMask, sync : ?fn (u64) void) *@This() {
    const cpuCount = @popCount(mask);

    // The maximum number of CPUs that can contend over a cacheline node
    const maxContention = 4;

    const numNodes = bin.alignUpNum(cpuCount, maxContention) / maxContention;

    const tree = bin.castPtr(*@This(), mem.pmallocBytes(@sizeOf(@This()) + numNodes * @sizeOf(*Node)));

    tree.mask = mask;
    tree.sync = if (sync == null) syncNull else sync;
    tree.curPeriod.store(0, .release);
    tree.maxContention = maxContention;

    var count : u8 = 0;
    createNodeRec(tree, null, cpuCount, &count, tree.mask, 0);

    return tree;
}

/// Free a cpu tree
pub fn free(tree : *@This()) void {
    const cpuCount = @popCount(tree.mask);
    const numNodes : u8 = bin.alignUpNum(cpuCount, tree.maxContention) / tree.maxContention;
    delNodeRec(tree, tree.leafNodes(), numNodes);

    mem.pfreeBytes(tree);
}

/// Report for a cpu
pub fn report(tree : *@This(), cpu_num : anytype) bool {
    const node = getNode(tree, cpu_num) orelse return true;

    var reported = false;

    node.spinlock.lock();

    if (node.cur & bin.setBit(cpu_num) == 1) reported = true;

    propagate(tree, node, bin.setBit(cpu_num));

    return reported;
}

/// Disable a cpu
pub fn disable(tree : *@This(), cpu_num : anytype) bool {
    const node = getNode(tree, cpu_num) orelse return false;

    var reported = false;

    node.spinlock.lock();

    bin.setFlag(cpu_num, &node.init);

    if (node.cur & bin.setBit(cpu_num) == 1) reported = true;

    propagate(tree, node, bin.setBit(cpu_num));

    return reported;
}

/// Enable a cpu
pub fn enable(tree : *@This(), cpu_num : anytype) void {
    const node = getNode(tree, cpu) orelse return;

    node.spinlock.lock();
    defer node.spinlock.unlock();

    bin.clearFlag(cpu_num, &node.init);
}