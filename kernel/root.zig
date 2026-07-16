pub const util = @import("util/root.zig");
pub const mm = @import("mm/root.zig");
pub const pm = @import("pm/root.zig");
pub const io = @import("io/root.zig");
pub const config = @import("config.zig");

const arch = @import("arch");
const std = @import("std");
const lib = @import("lib");
const limine = lib.limine;

comptime {
    _ = io.acpi;
    _ = pm.syscall.syscall;
}

/// ASM print
export fn xprint(val : u64) callconv(.c) void {
    print("xprint 0x{x} {b}\n", .{val, val});
}

pub const Limine = struct {
    const LIMINE_REQUESTS_START linksection(".limine_requests_start") = limine.LIMINE_REQUESTS_START_MARKER;

    pub var firmware_type linksection(".limine_requests") = limine.LimineFirmwareTypeRequest {};

    pub var hhdm_request linksection(".limine_requests") = limine.LimineHhdmRequest {};

    pub var mmap_request linksection(".limine_requests") = limine.LimineMemmapRequest {};

    pub var module_request linksection(".limine_requests") = limine.LimineModuleRequest {};

    pub var rsdp_request linksection(".limine_requests") = limine.LimineRsdpRequest {};

    pub var executable_file_request linksection(".limine_requests") = limine.LimineExecutableFileRequest {};

    pub var executable_address_request linksection(".limine_requests") = limine.LimineExecutableAddressRequest {};

    // Defined by the architecture. and just for reference here
    pub var smp_request : *limine.LimineMpRequest = undefined;

    const LIMINE_REQUESTS_END linksection(".limine_requests_end") = limine.LIMINE_REQUESTS_END_MARKER;

    /// Convert Limine HHDM-resolved addresses to physical
    pub fn toPhys(addr : *anyopaque) *anyopaque {
        return @ptrFromInt(@intFromPtr(addr) - hhdm_request.response.offset);
    }
};

// Common things that we want easy access to
pub const irqSave = io.irq.irqSave;
pub const irqRestore = io.irq.irqRestore;
pub const inIrq = io.irq.inIrq;
pub const noIrq = io.irq.noIrq;
pub const CpuMask = pm.process.CpuMask;
pub const cpuMaskFull = pm.process.cpuMaskFull;
pub const kernelProcess = &pm.process.kernelProcess;
pub const PerCpuDyn = pm.process.PerCpuDyn;
pub const PerCpuStat = pm.process.PerCpuStat;
pub const Process = pm.process.Process;
pub const Thread = pm.process.Thread;
pub const KThread = pm.process.KThread;
pub const UThread = pm.process.UThread;
pub const SmpRequest = io.irq.SmpRequest;

pub const RcuAsync = pm.ipc.rcu.RcuAsync;
pub const RcuPtr = pm.ipc.rcu.RcuPtr;
pub const Mutex = pm.ipc.Mutex;
pub const Semaphore = pm.ipc.Semaphore;

pub const Time = pm.time.Time;
pub const TimerEvent = pm.time.TimerEvent;
pub const getUnixClock = pm.time.getUnixClock;
pub const getMonoClock = pm.time.getMonoClock();

pub const cast = util.cast;

pub const pmalloc = mm.memory.pmalloc;
pub const pmallocBytes = mm.memory.pmallocBytes;
pub const pfree = mm.memory.pfree;
pub const pfreeBytes = mm.memory.pfreeBytes;
pub const vmalloc = mm.memory.vmalloc;
pub const vmallocBytes = mm.memory.vmallocBytes;
pub const vfree = mm.memory.vfree;
pub const vfreeBytes = mm.memory.vfreeBytes;
pub const memset = mm.memory.memset;
pub const memcpy = mm.memory.memcpy;
pub const Vaddr = mm.memory.Vaddr;
pub const Paddr = mm.memory.Paddr;
pub const allocPage = mm.buddyAlloc.allocPage;
pub const zallocPage = mm.buddyAlloc.zallocPage;
pub const allocPage4k = mm.buddyAlloc.allocPage4k;
pub const zallocPage4k = mm.buddyAlloc.zallocPage4k;
pub const freePage = mm.buddyAlloc.freePage;
pub const freePage4k = mm.buddyAlloc.freePage4k;
pub const SlubPool = mm.slubAlloc.SlubPool;
pub const SlubPoolTyped = mm.slubAlloc.SlubPoolTyped;
pub const PfeState = mm.paging.PfeState;

pub const bin = util.binary;
pub const Spinlock = util.Spinlock;
pub const RwLock = util.RwLock;
pub const types = util.types;

pub const AtomStack = util.data.AtomStack;
pub const Bitmap = util.data.Bitmap;
pub const List = util.data.List;
pub const Queue = util.data.Queue;
pub const Stack = util.data.Stack;

pub const log = util.log;
pub const print = log.print;

pub const cThread = pm.sched.scheduler.cThread;
pub const schedData = pm.sched.scheduler.schedData;

pub const irqEnable = arch.cpu.irqEnable;
pub const irqDisable = arch.cpu.irqDisable;
pub const irqEnabled = arch.cpu.irqEnabled;
pub const getCpuId = arch.cpu.getCpuId;
pub const CPU_FEATURES = &arch.cpu.FEATURES;
pub const CpuState = arch.cpu.CpuState;
pub const FpuState = arch.cpu.FpuState;
pub const MemFence = arch.cpu.MemFence;
