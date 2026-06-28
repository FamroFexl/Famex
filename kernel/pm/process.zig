const kernel = @import("kernel");
const mm = kernel.mm;
const vmm = mm.vmm;
const mem = mm.memory;
const paging = mm.paging;
const buddy = mm.buddy_alloc;
const util = kernel.util;
const log = util.log;
const bin = util.binary;
const types = util.types;
const sched = kernel.pm.sched.scheduler;
const cpu = @import("arch").cpu;

const std = @import("std");

pub const Process = struct {
    addr_space : vmm.VmSpace,
};

pub var kernelProcess : Process = undefined;

pub const CpuMask = u64;

pub fn cpuMaskFull() CpuMask {
    return bin.setBits(cpu.FEATURES.NUM_CPU_CORES);
}

pub const perCpu = struct {
    /// The minimum allocation size of a percpu variable
    pub const PER_CPU_DYN_ALLOC_BYTES = 64;

    /// For static percpu allocations, this is used to get the actual index relative to the percpu region
    pub var PER_CPU_LINKER_OFFSET : mem.Vaddr = undefined;

    /// This gets the offset that dynamic allocations start at
    pub var PER_CPU_STARTING_OFFSET : mem.Vaddr = undefined;

    pub var cur_offset : mem.Vaddr = .{.val = 0};

    /// Every bit in this is equivalent to 64 bytes
    pub var dyn_alloc_bmap : util.data.Bitmap = undefined;
    pub var dyn_alloc_bmap_lock : util.Spinlock = undefined;

    // Used for enabling preemption checks after initialization is complete
    pub var isSetup = false;
};

fn getLocalPercpu(comptime T: type, addr : u64) *T {
    // Get local percpu must execute without threat of being transferred to a new cpu
    std.debug.assert(!perCpu.isSetup or !cpu.irqEnabled() or sched.cThread().preemptDepth > 0);

    return @ptrFromInt(@intFromPtr(cpu.getPerCpu()) + addr);
}

fn getGlobalPercpu(comptime T: type, cpu_num : anytype, addr : u64) *T {
    return @ptrFromInt(mem.PER_CPU_DATA.val + mem.PER_CPU_DATA_SIZE * cpu_num + addr);
}

/// Static per-cpu allocation that is resolved at comptime
/// Use as "const per_cpu = PerCpuStat(u64);" or whatever type you need.
pub fn PerCpuStat(comptime T: type) type {
    return struct {
        const data: T linksection(".percpu") = undefined;

        pub fn getLocal() *T {
            return getLocalPercpu(T, @intFromPtr(&data) - perCpu.PER_CPU_LINKER_OFFSET.val);
        }

        pub fn getGlobal(cpu_num : anytype) *T {
            return getGlobalPercpu(T, cpu_num, @intFromPtr(&data) - perCpu.PER_CPU_LINKER_OFFSET.val);
        }
    };
}

/// Dynamic per-cpu allocations that are created at runtime
pub fn PerCpuDyn(comptime T: type) type {
    return struct {
        data : ?*T = null,

        pub fn alloc(self : *@This()) void {
            log.apanic(self.data != null, "pm: A percpu variable attempted to allocate when already allocated!\n", .{});

            const num = std.math.divCeil(u64, @sizeOf(T), perCpu.PER_CPU_DYN_ALLOC_BYTES) catch unreachable;
            var index : u64 = undefined;
            {
                perCpu.dyn_alloc_bmap_lock.lock();
                defer perCpu.dyn_alloc_bmap_lock.unlock();

                index = perCpu.dyn_alloc_bmap.findAndSet(num).?;
            }

            const cur = (index + num) * perCpu.PER_CPU_DYN_ALLOC_BYTES;
            if (cur > perCpu.cur_offset.val) {
                const last = perCpu.cur_offset.val + bin.alignUp(cur, types.SIZE_4KB);

                var pfe : mm.paging.Pte = mm.paging.PFE_DEFAULTS[0];
                pfe.setGlobal(0, true);

                for (0..cpu.FEATURES.NUM_CPU_CORES) |i| {
                    const percpu = @intFromPtr(getGlobalPercpu(*anyopaque, i, 0)) + perCpu.PER_CPU_STARTING_OFFSET.val;

                    var state = paging.PfeState.create(.MAP, &kernelProcess.addr_space, .{.val = percpu + perCpu.cur_offset.val}, .{.val = percpu + last}, .LEVEL_4KB);

                    while (true) {
                        const pte = state.mapNext() orelse break;
                        pte.* = pfe;
                        pte.setEntry(0, buddy.allocPage4k());
                    }
                }

                perCpu.cur_offset.val = last;
            }

            self.data = @ptrFromInt(perCpu.PER_CPU_STARTING_OFFSET.val + cur);
        }

        pub fn free(self : *@This()) void {
            log.apanic(self.data == null, "pm: A percpu variable attempted to free when it was already free!\n", .{});

            const addr = @intFromPtr(self.data);
            const bit_pos = (addr - perCpu.PER_CPU_STARTING_OFFSET.val) / perCpu.PER_CPU_DYN_ALLOC_BYTES;
            const bits = std.math.divCeil(u64, @sizeOf(T), perCpu.PER_CPU_DYN_ALLOC_BYTES) catch unreachable;

            {
                perCpu.dyn_alloc_bmap_lock.lock();
                defer perCpu.dyn_alloc_bmap_lock.unlock();

                perCpu.dyn_alloc_bmap.clear(bit_pos, bits);
            }
        }

        pub fn getLocal(self : *@This()) *T {
            return getLocalPercpu(T, @intFromPtr(self.data.?));
        }

        pub fn getGlobal(self : *@This(), cpu_num : anytype) *T {
            return getGlobalPercpu(T, cpu_num, @intFromPtr(self.data.?));
        }
    };
}

pub const Tid = u32;

pub const ThreadBase = struct {
    owner : *Process,
    tid : Tid,

    preemptDepth : u8,
    migrateDepth : u8,
};

pub const KThread = struct {
    base : ThreadBase,
};

pub const UThread = struct {
    base : ThreadBase,
};

pub fn preemptSave() void {
    irqSave();
    defer irqRestore();

    sched.cThread().preemptDepth += 1;
}

pub fn preemptRestore() void {
    irqSave();
    defer irqRestore();

    const data = sched.schedData.getLocal();
    const depth = &data.current.preemptDepth;
    depth.* -= 1;

    if (depth.* == 0 and data.flags.reschedule) {
        // yield_thread()
    }
}

/// Prevent cpu thread migration
pub fn migrateSave() void {
    irqSave();
    defer irqRestore();

    const data = sched.schedData.getLocal();
    data.current.migrateDepth += 1;
}

/// Enable cpu thread migration
pub fn migrateRestore() void {
    irqSave();
    defer irqRestore();

    const data = sched.schedData.getLocal();
    data.current.migrateDepth -= 1;
}

const irqSaveDepth = PerCpuStat(u64);

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

pub export fn inKmode(state : *cpu.CpuState) bool {
    return state.getStack() >= mem.KERNEL_MEMORY.val;
}
