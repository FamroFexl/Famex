const std = @import("std");

const kernel = @import("kernel");
const mem = kernel.mm.memory;
const bin = kernel.util.binary;
const print = kernel.util.log.print;

const acpica = @import("lib").acpica;

pub var ACPI_INITIALIZED = false;

export fn AcpiOsInitialize() acpica.ACPI_STATUS {
    return acpica.AE_OK;
}

export fn AcpiOsTerminate() acpica.ACPI_STATUS {
    return acpica.AE_OK;
}

export fn AcpiOsGetRootPointer() acpica.ACPI_PHYSICAL_ADDRESS {
    return @intFromPtr(kernel.Limine.rsdp_request.response.address);
}

export fn AcpiOsPredefinedOverride(initVal : ?*const acpica.ACPI_PREDEFINED_NAMES, newVal : ?*acpica.ACPI_STRING) acpica.ACPI_STATUS {
    _ = initVal;

    if (newVal == null) return acpica.AE_BAD_PARAMETER;
    newVal.?.* = null;
    return acpica.AE_OK;
}

export fn AcpiOsTableOverride(existingTable : *acpica.ACPI_TABLE_HEADER, newTable : ?**acpica.ACPI_TABLE_HEADER) acpica.ACPI_STATUS {
    _ = existingTable;

    if (newTable == null) return acpica.AE_BAD_PARAMETER;

    newTable.?.* = bin.castPtr(*acpica.ACPI_TABLE_HEADER, @ptrFromInt(32));
    return acpica.AE_OK;
}

export fn AcpiOsPhysicalTableOverride(existingTable : ?*acpica.ACPI_TABLE_HEADER, newAddress : ?*acpica.ACPI_PHYSICAL_ADDRESS, newTableLength : ?*u32) acpica.ACPI_STATUS {
    if (newAddress == null or newTableLength == null) return acpica.AE_BAD_PARAMETER;

    _ = existingTable;
    newAddress.?.* = 0;
    newTableLength.?.* = 0;
    return acpica.AE_OK;
}

export fn AcpiOsCreateLock(outHandle : ?*acpica.ACPI_SPINLOCK) acpica.ACPI_STATUS {
    const handle = outHandle orelse return acpica.AE_BAD_PARAMETER;

    const spinlock = mem.pmalloc(kernel.util.Spinlock);
    spinlock.init();

    handle.* = spinlock;

    return acpica.AE_OK;
}

export fn AcpiOsDeleteLock(inHandle : acpica.ACPI_SPINLOCK) void {
    const handle = inHandle orelse return;
    const spinlock = bin.castPtr(*kernel.util.Spinlock, handle);
    mem.pfree(kernel.util.Spinlock, spinlock);
}

export fn AcpiOsAcquireLock(inHandle : acpica.ACPI_SPINLOCK) acpica.ACPI_CPU_FLAGS {
    const spinlock = bin.castPtr(*kernel.util.Spinlock, inHandle.?);
    spinlock.lock();
    return 0;
}

export fn AcpiOsReleaseLock(inHandle : acpica.ACPI_SPINLOCK, flags : acpica.ACPI_CPU_FLAGS) void {
    const handle = inHandle orelse return;
    _ = flags;
    const spinlock = bin.castPtr(*kernel.util.Spinlock, handle);
    spinlock.unlock();
}

export fn AcpiOsCreateMutex(outHandle : ?*acpica.ACPI_MUTEX) acpica.ACPI_STATUS {
    const handle = outHandle orelse return acpica.AE_BAD_PARAMETER;

    const mutex = mem.pmalloc(kernel.pm.ipc.Mutex);
    mutex.init();

    handle.* = mutex;

    return acpica.AE_OK;
}

export fn AcpiOsDeleteMutex(inHandle : acpica.ACPI_MUTEX) void {
    const handle = inHandle orelse return;
    const mutex = bin.castPtr(*kernel.pm.ipc.Mutex, handle);
    mem.pfree(kernel.pm.ipc.Mutex, mutex);
}

export fn AcpiOsAcquireMutex(inHandle : acpica.ACPI_MUTEX, timeout : u16) acpica.ACPI_STATUS {
    _ = timeout;
    if (!ACPI_INITIALIZED) return acpica.AE_OK;

    const handle = inHandle orelse return acpica.AE_BAD_PARAMETER;
    const mutex = bin.castPtr(*kernel.pm.ipc.Mutex, handle);
    mutex.acquire();

    return acpica.AE_OK;
}

export fn AcpiOsReleaseMutex(inHandle : acpica.ACPI_MUTEX) acpica.ACPI_STATUS {
    if (!ACPI_INITIALIZED) return acpica.AE_OK;

    const handle = inHandle orelse return acpica.AE_BAD_PARAMETER;
    const mutex = bin.castPtr(*kernel.pm.ipc.Mutex, handle);
    mutex.release();

    return acpica.AE_OK;
}

export fn AcpiOsCreateSemaphore(maxUnits : u32, initialUnits : u32, outHandle : ?*acpica.ACPI_SEMAPHORE) acpica.ACPI_STATUS {
    const handle = outHandle orelse return acpica.AE_BAD_PARAMETER;

    const semaphore = mem.pmalloc(kernel.pm.ipc.Semaphore);
    semaphore.init(maxUnits);
    semaphore.curCount = initialUnits;

    handle.* = semaphore;

    return acpica.AE_OK;
}

export fn AcpiOsDeleteSemaphore(inHandle : acpica.ACPI_SEMAPHORE) acpica.ACPI_STATUS {
    const handle = inHandle orelse return acpica.AE_BAD_PARAMETER;
    const semaphore = bin.castPtr(*kernel.pm.ipc.Semaphore, handle);
    mem.pfree(kernel.pm.ipc.Semaphore, semaphore);

    return acpica.AE_OK;
}

export fn AcpiOsWaitSemaphore(inHandle : acpica.ACPI_SEMAPHORE, units : u32, timeout : u16) acpica.ACPI_STATUS {
    _ = units;
    _ = timeout;
    if (!ACPI_INITIALIZED) return acpica.AE_OK;

    const handle = inHandle orelse return acpica.AE_BAD_PARAMETER;

    const semaphore = bin.castPtr(*kernel.pm.ipc.Semaphore, handle);
    semaphore.acquire();

    return acpica.AE_OK;
}

export fn AcpiOsSignalSemaphore(inHandle : acpica.ACPI_SEMAPHORE, units : u32) acpica.ACPI_STATUS {
    _ = units;
    if (!ACPI_INITIALIZED) return acpica.AE_OK;

    const handle = inHandle orelse return acpica.AE_BAD_PARAMETER;
    const semaphore = bin.castPtr(*kernel.pm.ipc.Semaphore, handle);

    semaphore.release();

    return acpica.AE_OK;
}

export fn AcpiOsAllocate(size : acpica.ACPI_SIZE) *anyopaque {
    return mem.pmallocBytes(size);
}

export fn AcpiOsFree(memory : ?*anyopaque) void {
    if (memory == null) return;
    mem.pfreeBytes(memory.?);
}

export fn AcpiOsMapMemory(where : acpica.ACPI_PHYSICAL_ADDRESS, length : acpica.ACPI_SIZE) *anyopaque {
    _ = length;
    return mem.Paddr.asPhys(where).toVirt().ptr();
}

export fn AcpiOsUnmapMemory(logicalAddress : ?*anyopaque, size : acpica.ACPI_SIZE) void {
    _ = logicalAddress;
    _ = size;
}

export fn AcpiOsGetPhysicalAddress(logicalAddress : ?*anyopaque, physicalAddress : ?*acpica.ACPI_PHYSICAL_ADDRESS) acpica.ACPI_STATUS {
    if (logicalAddress == null or physicalAddress == null) return acpica.AE_BAD_PARAMETER;

    const vaddr = mem.Vaddr.asVirt(@intFromPtr(logicalAddress));
    physicalAddress.?.* = vaddr.toPhys().val;

    return acpica.AE_OK;
}

export fn AcpiOsPrintf(format : [*:0]const u8, ...) void {
    _ = format;
}

export fn AcpiOsVprintf(format : [*:0]const u8, args: ?*anyopaque) void {
    _ = format;
    _ = args;
}


export fn AcpiOsInstallInterruptHandler(irqNumber : u32, serviceRoutine : acpica.ACPI_OSD_HANDLER, context : ?*anyopaque) acpica.ACPI_STATUS {
    _ = irqNumber;
    _ = serviceRoutine;
    _ = context;

    return acpica.AE_OK;
}

export fn AcpiOsRemoveInterruptHandler(irqNumber : u32, serviceRoutine : acpica.ACPI_OSD_HANDLER) acpica.ACPI_STATUS {
    _ = irqNumber;
    _ = serviceRoutine;

    return acpica.AE_OK;
}

export fn AcpiOsSignal(function : u32, info : ?*anyopaque) acpica.ACPI_STATUS {
    _ = function;
    _ = info;

    return acpica.AE_OK;
}

export fn AcpiOsGetTimer() u64 {
    return 0;
}

export fn AcpiOsGetThreadId() acpica.ACPI_THREAD_ID {
    if (!ACPI_INITIALIZED) return 0;

    return kernel.pm.sched.scheduler.cThread().tid;
}

export fn AcpiOsReadPciConfiguration(pciId : acpica.ACPI_PCI_ID, register : u32, value : *u64, width : u32) acpica.ACPI_STATUS {
    _ = pciId;
    _ = register;
    _ = value;
    _ = width;

    return acpica.AE_OK;
}

export fn AcpiOsWritePciConfiguration(pciId : acpica.ACPI_PCI_ID, register : u32, value : *u64, width : u32) acpica.ACPI_STATUS {
    _ = pciId;
    _ = register;
    _ = value;
    _ = width;

    return acpica.AE_OK;
}

export fn AcpiOsEnterSleep(sleepState : u8, regAValue : u32, regBValue : u32) acpica.ACPI_STATUS {
    _ = sleepState;
    _ = regAValue;
    _ = regBValue;

    return acpica.AE_OK;
}

export fn AcpiOsExecute(execType : acpica.ACPI_EXECUTE_TYPE, function : acpica.ACPI_OSD_EXEC_CALLBACK, context : ?*anyopaque) acpica.ACPI_STATUS {
    _ = execType;
    _ = function;
    _ = context;

    return acpica.AE_OK;
}

export fn AcpiOsWaitEventsComplete() void {

}

export fn AcpiOsSleep(milliseconds : u64) void {
    _ = milliseconds;
}

export fn AcpiOsStall(microseconds : u32) void {
    _ = microseconds;
}

export fn AcpiOsReadPort(address : acpica.ACPI_IO_ADDRESS, value : ?*u32, width : u32) acpica.ACPI_STATUS {
    _ = address;
    _ = value;
    _ = width;

    return acpica.AE_OK;
}

export fn AcpiOsWritePort(address : acpica.ACPI_IO_ADDRESS, value : u32, width : u32) acpica.ACPI_STATUS {
    _ = address;
    _ = value;
    _ = width;

    return acpica.AE_OK;
}

export fn AcpiOsReadMemory(address : acpica.ACPI_PHYSICAL_ADDRESS, value : ?*u64, width : u32) acpica.ACPI_STATUS {
    if (value == null) return acpica.AE_BAD_PARAMETER;
    if (address == 0) return acpica.AE_ERROR;

    const vaddr = mem.Paddr.asPhys(address).toVirt();

    mem.memcpy(value.?, vaddr.ptr(), width);

    return acpica.AE_OK;
}

export fn AcpiOsWriteMemory(address : acpica.ACPI_PHYSICAL_ADDRESS, value : ?*u64, width : u32) acpica.ACPI_STATUS {
    if (value == null) return acpica.AE_BAD_PARAMETER;
    if (address == 0) return acpica.AE_ERROR;

    const vaddr = mem.Paddr.asPhys(address).toVirt();

    mem.memcpy(vaddr.ptr(), value.?, width);

    return acpica.AE_OK;
}

fn registerHandlers() void {
    //AcpiInstallInitializationHandler();
    //AcpiInstallTableHandler();
    //AcpiInstallExceptionHandler();
    //AcpiInstallAddressSpaceHandler();
    //AcpiInstallFixedEventHandler();
    //AcpiInstallGpeHandler();
    //AcpiInstallNotifyHandler();
}

pub fn setupSubsys() void {
    acpica.AcpiEnableSubsystem(0);

    registerHandlers();

    acpica.AcpiInitializeObjects(0);
}

pub fn setupTables() void {
    print("\ninit: Initializing ACPI Tables\n", .{});
    const tables = mem.pmallocBytes(@sizeOf(acpica.ACPI_TABLE_DESC) * 16);
    _ = acpica.AcpiInitializeTables(@ptrCast(@alignCast(tables)), 16, 1);

    print("  ACPI Tables: ", .{});
    for (0..10) |i| {
        const table : [*c][*c]acpica.ACPI_TABLE_HEADER = null;
        const status = acpica.AcpiGetTableByIndex(@intCast(i), table);
        if (status == acpica.AE_BAD_PARAMETER) break;
        print("{s:4}", .{table.?.*.*.Signature});
    }
}