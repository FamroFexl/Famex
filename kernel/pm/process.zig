const kernel = @import("kernel");
const mm = kernel.mm;
const vmm = mm.vmm;
const mem = mm.memory;
const paging = mm.paging;
const buddy = mm.buddyAlloc;
const util = kernel.util;
const log = util.log;
const bin = util.binary;
const types = util.types;
const sched = kernel.pm.sched.scheduler;
const time = @import("time.zig");
const cpu = @import("arch").cpu;

const lib = @import("lib");

const std = @import("std");

pub const Pid = i32;

/// Map of Process IDs to processes
pub var pids : lib.linux.XArray = undefined;
/// Map of Thread IDs to threads
pub var tids : lib.linux.XArray = undefined;

pub const Process = struct {
    parent : ?*@This(),
    addrSpace : vmm.VmSpace,
    state : State,

    timeLock : kernel.RwLock = .create(),
    createTime : kernel.Time,           // Process creation time
    termUTime : kernel.Time = .zero(),  // User-mode time of all terminated child processes
    termKTime : kernel.Time = .zero(),  // Kernel-mode time of all terminated child processes

    pid : Pid = undefined,

    threads : util.data.List,
    children : util.data.List,

    creds : struct {
        ruid : lib.posix.types.uid_t,   // Real User ID
        euid : lib.posix.types.uid_t,   // Effective User ID
        suid : lib.posix.types.uid_t,   // Saved User ID

        rgid : lib.posix.types.uid_t,   // Real Group ID
        egid : lib.posix.types.uid_t,   // Effective Group ID
        sgid : lib.posix.types.uid_t,   // Saved Group ID
    },

    const State = enum {
        RUNNING,       // The process is running
        STOPPED,       // The process has been stopped (all threads THRD_STOPPED)
        ZOMBIE,        // The process is waiting to be reaped
    };
};

pub const Tid = u32;

pub const Thread = struct {
    owner : *Process = undefined,
    state : State = undefined,
    flags : packed struct {
    } = undefined,

    context : kernel.CpuState = undefined,
    tid : Tid = undefined,

    timeLock : kernel.RwLock = .create(),
    ktime : kernel.Time = .zero(),

    preemptDepth : u8 = 0,
    migrateDepth : u8 = 0,

    /// Kernel stack data
    stack : Stack = undefined,

    schedLink : kernel.List.Node = undefined,
    sched : struct {
        policy : sched.Policy,
        priority : u8,  // FIFO/RR real-time priority
        nice : i8,      // Nice value for NORMAL policy
    } = undefined,

    /// Semaphore and mutex sleep link
    sleepLink : util.data.Queue.Node = undefined,

    /// Process thread link
    link : kernel.List.Node = undefined,

    const State = enum {
        RUNNING,           // Is running or waiting to start running
        INTERRUPTABLE,     // Interruptable sleep
        UNINTERRUPTIBLE,   // Uninterruptable sleep
        STOPPED,           // Suspended by unblockable signal (SIGSTOP)
        DEAD               // Being cleaned up
    };

    /// Thread stack structure
    pub const Stack = struct {
        start : u64,
        size : usize,
    };

    pub fn preemptSave(this : *@This()) void {
        kernel.irqSave();
        defer kernel.irqRestore();

        this.preemptDepth += 1;
    }

    pub fn preemptRestore(this : *@This()) void {
        kernel.irqSave();
        defer kernel.irqRestore();

        this.preemptDepth -= 1;

        if (this.preemptDepth == 0 and sched.schedData.getLocal().flags.reschedule) {
            this.yield();
        }
    }

    /// Prevent cpu thread migration
    pub fn migrateSave(this : *@This()) void {
        kernel.irqSave();
        defer kernel.irqRestore();

        this.migrateDepth += 1;
    }

    /// Enable cpu thread migration
    pub fn migrateRestore(this : *@This()) void {
        kernel.irqSave();
        defer kernel.irqRestore();

        this.migrateDepth -= 1;
    }

    pub fn yield(this : *@This()) void { kernel.noIrq();
        std.debug.assert(!kernel.irqEnabled());

        const scheduler = &sched.schedData.getLocal().sched.get(this.sched.policy);
        scheduler.onYield(scheduler, this);
        sched.switchThread();
    }

    pub fn sleep(this : *@This()) void { kernel.noIrq();
        this.state = .INTERRUPTABLE;

        const scheduler = &sched.schedData.getLocal().sched.get(this.sched.policy);
        scheduler.onSleep(scheduler, this);
        sched.switchThread();
    }

    pub fn wake(this : *@This()) void { kernel.noIrq();
        const scheduler = &sched.schedData.getLocal().sched.get(this.sched.policy);
        scheduler.onWake(scheduler, this);

        this.state = .RUNNING;
    }

    pub fn container(this: *@This()) union(enum) {
        kThread : *KThread,
        uThread : *UThread,
    } {
        return if (this.owner == &kernelProcess)
            .{ .kThread = @fieldParentPtr("base", this), }
        else
            .{ .uThread = @fieldParentPtr("base", this), };
    }
};

pub const KThread = struct {
    base : Thread,
};

pub const UThread = struct {
    base : Thread,
    flags : packed struct {
        inSyscall : bool = undefined,
    },
    utime : kernel.Time,

    fpuContext : kernel.FpuState,
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
    // Preempt depth doesn't guarantee non-corruption since interrupts can access percpu vars as well
    std.debug.assert(!perCpu.isSetup or !cpu.irqEnabled() or sched.cThread().preemptDepth > 0);

    return @ptrFromInt(@intFromPtr(cpu.getPerCpu()) + addr);
}

fn getGlobalPercpu(comptime T: type, cpu_num : anytype, addr : u64) *T {
    return @ptrFromInt(mem.PER_CPU_DATA.val + mem.PER_CPU_DATA_SIZE * cpu_num + addr);
}

/// Occupies the start of the per-cpu region, for offset-based
/// stack pointer access, etc
pub const perCpuStart = struct {
    var data : kernel.io.asmLayout.PerCpuStart linksection(".percpu.start") = undefined;

    pub fn getLocal() *kernel.io.asmLayout.PerCpuStart {
        return getLocalPercpu(kernel.io.asmLayout.PerCpuStart, @intFromPtr(&data) - perCpu.PER_CPU_LINKER_OFFSET.val);
    }

    pub fn getGlobal(cpu_num : anytype) *kernel.io.asmLayout.PerCpuStart {
        return getGlobalPercpu(kernel.io.asmLayout.PerCpuStart, cpu_num, @intFromPtr(&data) - perCpu.PER_CPU_LINKER_OFFSET.val);
    }
};

/// Static per-cpu allocation that is resolved at comptime
/// Use as "const per_cpu = PerCpuStat(u64, opaque {});"
pub fn PerCpuStat(comptime T: type, comptime tag : type) type {
    return struct {
        // Used to prevent type coalescing, which would make two PerCpuStat with the same T the same type
        const distinct = tag;
        var data : T linksection(".percpu") = undefined;

        pub fn getLocal() *T {
            return getLocalPercpu(T, @intFromPtr(&data) - perCpu.PER_CPU_LINKER_OFFSET.val);
        }

        pub fn getGlobal(cpu_num : anytype) *T {
            return getGlobalPercpu(T, cpu_num, @intFromPtr(&data) - perCpu.PER_CPU_LINKER_OFFSET.val);
        }
    };
}

/// Dynamic per-cpu allocation that is created at runtime
/// Use as "field : PerCpuDyn(u64),"
pub fn PerCpuDyn(comptime T: type) type {
    return struct {
        data : ?*T = null,

        pub fn alloc(this : *@This()) void {
            log.apanic(this.data != null, "pm: A percpu variable attempted to allocate when already allocated!\n", .{});

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

                    var state = kernel.PfeState(.MAP).create(&kernelProcess.addrSpace, .{.val = percpu + perCpu.cur_offset.val}, .{.val = percpu + last}, .LEVEL_4KB);
                    while (state.next()) |pte| {
                        pte.* = pfe;
                        pte.setEntry(0, buddy.allocPage4k());
                    }
                }

                perCpu.cur_offset.val = last;
            }

            this.data = @ptrFromInt(perCpu.PER_CPU_STARTING_OFFSET.val + cur);
        }

        pub fn free(this : *@This()) void {
            log.apanic(this.data == null, "pm: A percpu variable attempted to free when it was already free!\n", .{});

            const addr = @intFromPtr(this.data);
            const bit_pos = (addr - perCpu.PER_CPU_STARTING_OFFSET.val) / perCpu.PER_CPU_DYN_ALLOC_BYTES;
            const bits = std.math.divCeil(u64, @sizeOf(T), perCpu.PER_CPU_DYN_ALLOC_BYTES) catch unreachable;

            {
                perCpu.dyn_alloc_bmap_lock.lock();
                defer perCpu.dyn_alloc_bmap_lock.unlock();

                perCpu.dyn_alloc_bmap.clear(bit_pos, bits);
            }
        }

        pub fn getLocal(this : *@This()) *T {
            return getLocalPercpu(T, @intFromPtr(this.data.?));
        }

        pub fn getGlobal(this : *@This(), cpu_num : anytype) *T {
            return getGlobalPercpu(T, cpu_num, @intFromPtr(this.data.?));
        }
    };
}

pub const startTime = PerCpuStat(u64, opaque {});

pub fn startTimeReset() u64 {
    const mono = time.getMonoClock();
    const localStart = startTime.getLocal();

    const out = mono.nsec - localStart.*;
    localStart.* = mono.nsec;

    return out;
}

pub fn addKtime() void {
    const ktime = startTimeReset();

    const cThread = sched.cThread();

    cThread.timeLock.writeLock();
    cThread.ktime.nsec += ktime;
    cThread.timeLock.writeUnlock();
}

pub fn addUtime() void {
    const utime = startTimeReset();

    const cThread = sched.cThread();
    const uThread : *UThread = @fieldParentPtr("base", cThread);

    cThread.timeLock.writeLock();
    uThread.utime.nsec += utime;
    cThread.timeLock.writeUnlock();
}

pub extern fn inKmode(state : *kernel.CpuState) callconv(.c) bool;

fn setupKernelProc() void {
    pids.set(0, &kernelProcess);
    kernelProcess.pid = 0;
    kernelProcess.state = .RUNNING;
    kernelProcess.createTime = time.getUnixClock();
    kernelProcess.parent = null;
    kernelProcess.threads.init();
    kernelProcess.children.init();
    kernelProcess.timeLock.init();
}

pub fn setup() void {
    kernel.print("pm: Setting up Processing\n", .{});

    pids.init(true);
    tids.init(true);

    kernel.pm.sched.scheduler.setup();

    setupKernelProc();
}
