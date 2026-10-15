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

const signal = @import("signal.zig");

const lib = @import("lib");

const std = @import("std");

pub const Pid = i32;

/// Map of Process IDs to processes
pub var pids : lib.linux.XArray = undefined;
/// Map of Thread IDs to threads
pub var tids : lib.linux.XArray = undefined;

pub var pgids : lib.linux.XArray = undefined;

const PgidList = kernel.ListTyped(Pgid, "sessionLink");

pub const Session = struct {
    pid : Pid, // Pid of the session leader
    list : PgidList, // List of all pgid members
};

const PgidProcList = kernel.ListTyped(Process, "pgidLink");

pub const Pgid = struct {
    pid : Pid,  // Pid of the process group
    list : PgidProcList, // List of all process members
    sessionLink : PgidList.Node, // Link for sessions
    session : *Session, // Session pointer
};

const ProcessList = kernel.ListTyped(Process, "link");
const ThreadList = kernel.ListTyped(Thread, "link");

pub const Process = struct {
    spinlock : kernel.Spinlock = .create(),

    parent : ?*@This(),
    addrSpace : vmm.VmSpace = undefined,
    state : State = undefined,

    createTime : kernel.Time,           // Process creation time
    termUTime : kernel.Time = .zero(),  // User-mode time of all terminated child processes
    termKTime : kernel.Time = .zero(),  // Kernel-mode time of all terminated child processes
    utime : kernel.Time = .zero(),      // User-mode time of all threads
    ktime : kernel.Time = .zero(),      // Kernel-mode time of all threads

    pid : Pid,

    pgid : *Pgid = undefined,
    pgidLink : PgidProcList.Node = undefined,

    sigAction : [lib.posix.signal.SIGRTMAX]lib.posix.signal.sigaction = [_]lib.posix.signal.sigaction{.{
        .sa_flags = .{},
        .sa_handler = .SIG_DFL,
        .sa_mask = 0,
    }} ** lib.posix.signal.SIGRTMAX,
    sigData : signal.SigData = undefined,

    sigAlarm : kernel.TimerEvent = .create(.MONOTONIC, .Msec(100), kernel.pm.signal.sigAlarmCallback),
    timers : [lib.posix.limits.TIMER_MAX]kernel.pm.syscall.syscall.ProcTimer = [_]kernel.pm.syscall.syscall.ProcTimer{.{}} ** lib.posix.limits.TIMER_MAX,   // Process timers
    timersLock : kernel.Spinlock = .create(),   // Process timers lock

    threads : ThreadList = undefined,
    children : ProcessList = undefined,

    link : ProcessList.Node,

    creds : struct {
        ruid : lib.posix.types.uid_t = undefined,   // Real User ID
        euid : lib.posix.types.uid_t = undefined,   // Effective User ID
        suid : lib.posix.types.uid_t = undefined,   // Saved User ID

        rgid : lib.posix.types.uid_t = undefined,   // Real Group ID
        egid : lib.posix.types.uid_t = undefined,   // Effective Group ID
        sgid : lib.posix.types.uid_t = undefined,   // Saved Group ID
    } = undefined,

    flags : packed struct {
        HAS_EXECED : bool,  // Process has switched execution
    },

    const State = enum {
        RUNNING,       // The process is running
        STOPPED,       // The process has been stopped (all threads THRD_STOPPED)
        ZOMBIE,        // The process is waiting to be reaped
    };
};

pub const Tid = u32;

pub const Thread = struct {
    spinlock : kernel.Spinlock = .create(),

    owner : *Process = undefined,
    state : State = undefined,
    flags : packed struct {
    } = undefined,

    context : kernel.CpuState = undefined,
    fpuContext : ?kernel.FpuState = null,
    tid : Tid = undefined,

    ktime : kernel.Time = .zero(),

    irqSaveDepth : u64 = 0,
    preemptDepth : u8 = 0,
    migrateDepth : u8 = 0,

    /// Kernel stack data
    stack : Stack = undefined,

    schedLink : sched.SchedList.Node = undefined,
    sched : struct {
        policy : sched.Policy,
        priority : u8,  // FIFO/RR real-time priority
        nice : i8,      // Nice value for NORMAL policy
    } = undefined,

    /// Semaphore and mutex sleep link
    sleepLink : kernel.util.WaitQueue.Node = undefined,
    wakeReason : enum {
        TIMER_EXPIRED,
        SIGNAL_RECEIVED
    } = undefined,

    /// Process thread link
    link : ThreadList.Node = undefined,

    pub const State = enum {
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

    pub fn yield(this : *@This()) void { kernel.irqSaved(); kernel.util.locks.noLocksHeld();
        const scheduler = &sched.schedData.getLocal().sched.get(this.sched.policy);
        scheduler.onYield(scheduler, this);
        sched.switchThread();
    }

    pub fn sleep(this : *@This()) void { kernel.irqSaved(); kernel.util.locks.noLocksHeld();
        this.spinlock.lock();

        if (this.state != .RUNNING) {
            this.spinlock.unlock();
            return;
        }
        this.spinlock.unlock();

        const scheduler = &sched.schedData.getLocal().sched.get(this.sched.policy);
        scheduler.onSleep(scheduler, this);
        sched.switchThread();
    }

    pub fn wake(this : *@This()) void { kernel.irqSaved();
        const scheduler = &sched.schedData.getLocal().sched.get(this.sched.policy);
        scheduler.onWake(scheduler, this);
        sched.reschedule();
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

    uStack : *vmm.VmArea,

    sigMask : lib.posix.signal.sigset_t = 0,
    sigAltStack : lib.posix.signal.stack_t = .{
        .ss_flags = .{ .SS_DISABLE = true, .SS_ONSTACK = false},
        .ss_size = undefined,
        .ss_sp = undefined,
    },
    sigData : signal.SigData = undefined,

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

pub fn getCpuTime(clockId : lib.posix.types.clockid_t) ?u64 {
    switch (lib.posix.times.getClockFromId(clockId)) {
        .PROCESS_CPUTIME_ID => {
            const process = kernel.cast.toPtr(*kernel.Process, pids.get(@intCast(lib.posix.times.getPidFromId(clockId))) orelse return null);
            process.spinlock.lock();
            defer process.spinlock.unlock();

            return process.ktime.nsec + process.utime.nsec;
        },
        .THREAD_CPUTIME_ID => {
            const thread = kernel.cast.toPtr(*kernel.Thread, tids.get(@intCast(lib.posix.times.getTidFromId(clockId))) orelse return null);

            thread.spinlock.lock();
            defer thread.spinlock.unlock();

            return thread.ktime.nsec + switch (thread.container()) {
                .uThread => |uThread| uThread.utime.nsec,
                .kThread => 0
            };
        },
        else => return null,
    }
}

fn checkCpuTimers(thread : *Thread) void {
    const process = thread.owner;

    process.timersLock.lock();

    // Iterate through all timers
    for (&thread.owner.timers) |*timer| {
        if (!timer.inUse or timer.timerType != .cpuTimer or !timer.armed)
            continue;

        const curTime = getCpuTime(timer.timerType.cpuTimer.clockId) orelse undefined;

        if (curTime > timer.timerType.cpuTimer.expiration.nsec)
            continue;

        if (timer.reset) |res|
             timer.timerType.cpuTimer.expiration.nsec += res.nsec;

        if (timer.signot != .SIGEV_SIGNAL)
            continue;

        const timerNum = (@intFromPtr(timer) - @intFromPtr(&thread.owner.timers)) / @sizeOf(kernel.pm.syscall.syscall.ProcTimer);

        var overrun = false;

        process.timersLock.unlock();

        kernel.pm.signal.sigSend(.PROCESS, process, .{
            .si_signo = timer.signo,
            .si_value = timer.sigval,
            .si_code = .SI_TIMER,
            .si_status = @intCast(timerNum),
        }) catch |err| switch (err) {
            error.TimerIsQueued => overrun = true,
            else => unreachable,
        };

        process.timersLock.lock();

        if (overrun) {
            timer.overrun += 1;
        }
        else {
            timer.overrun = 0;
        }
    }

    process.timersLock.unlock();
}

pub fn addKtime() void {
    const ktime = startTimeReset();

    const cThread = sched.cThread();

    cThread.spinlock.lock();
    cThread.ktime.nsec += ktime;
    cThread.spinlock.unlock();

    cThread.owner.spinlock.lock();
    cThread.owner.ktime.nsec += ktime;
    cThread.owner.spinlock.unlock();

    checkCpuTimers(cThread);
}

pub fn addUtime() void {
    const utime = startTimeReset();

    const cThread = sched.cThread();

    cThread.spinlock.lock();
    cThread.container().uThread.utime.nsec += utime;
    cThread.spinlock.unlock();

    cThread.owner.spinlock.lock();
    cThread.owner.utime.nsec += utime;
    cThread.owner.spinlock.unlock();

    checkCpuTimers(cThread);
}

fn setupKernelProc() void {
    pids.set(0, &kernelProcess);
    kernelProcess.pid = 0;
    kernelProcess.state = .RUNNING;
    kernelProcess.createTime = time.getUnixClock();
    kernelProcess.parent = null;
    kernelProcess.threads.init();
    kernelProcess.children.init();

    kernelProcess.pgid = kernel.pmalloc(Pgid);
    pgids.set(0, kernelProcess.pgid);
    kernelProcess.pgid.pid = 0;
    kernelProcess.pgid.list.init();
    kernelProcess.pgid.list.insertFront(kernelProcess);

    kernelProcess.pgid.session = kernel.pmalloc(Session);
    kernelProcess.pgid.session.pid = 0;
    kernelProcess.pgid.session.list.init();
    kernelProcess.pgid.session.list.insertFront(kernelProcess.pgid);
}

pub fn setup() void {
    kernel.print("pm: Setting up Processing\n", .{});

    pids.init(true);
    tids.init(true);
    pgids.init(false);

    kernel.pm.sched.scheduler.setup();

    setupKernelProc();

    kernel.pm.syscall.syscall.setup();
}
