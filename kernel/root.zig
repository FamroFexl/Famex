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
};

// Common things that we want easy access to
pub const preemptSave = pm.process.preemptSave;
pub const preemptRestore = pm.process.preemptRestore;
pub const migrateSave = pm.process.migrateSave;
pub const migrateRestore = pm.process.migrateRestore;
pub const irqSave = pm.process.irqSave;
pub const irqRestore = pm.process.irqRestore;
pub const CpuMask = pm.process.CpuMask;
pub const cpuMaskFull = pm.process.cpuMaskFull;
pub const kernelProcess = pm.process.kernelProcess;
pub const PerCpuDyn = pm.process.PerCpuDyn;
pub const PerCpuStat = pm.process.PerCpuStat;
pub const Process = pm.process.Process;
pub const ThreadBase = pm.process.ThreadBase;
pub const KThread = pm.process.KThread;
pub const UThread = pm.process.UThread;
pub const RcuPtr = pm.ipc.rcu.RcuPtr;
pub const RcuFree = pm.ipc.rcu.RcuFree;
pub const Mutex = pm.ipc.Mutex;
pub const Semaphore = pm.ipc.Semaphore;

pub const pmalloc = mm.memory.pmalloc;
pub const pmallocBytes = mm.memory.pmallocBytes;
pub const pfree = mm.memory.pfree;
pub const pfreeBytes = mm.memory.pfreeBytes;
pub const memset = mm.memory.memset;
pub const memcpy = mm.memory.memcpy;
pub const Vaddr = mm.memory.Vaddr;
pub const Paddr = mm.memory.Paddr;
pub const allocPage = mm.buddy_alloc.allocPage;
pub const zallocPage = mm.buddy_alloc.zallocPage;
pub const allocPage4k = mm.buddy_alloc.allocPage4k;
pub const zallocPage4k = mm.buddy_alloc.zallocPage4k;
pub const freePage = mm.buddy_alloc.freePage;
pub const freePage4k = mm.buddy_alloc.freePage4k;
pub const SlubPool = mm.slub_alloc.SlubPool;
pub const SlubPoolTyped = mm.slub_alloc.SlubPoolTyped;
pub const PfeState = mm.paging.PfeState;

pub const bin = util.binary;
pub const Spinlock = util.Spinlock;
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
pub const CPU_FEATURES = arch.cpu.FEATURES;
pub const CpuState = arch.cpu.CpuState;
pub const FpuState = arch.cpu.FpuState;
pub const MemFence = arch.cpu.MemFence;
