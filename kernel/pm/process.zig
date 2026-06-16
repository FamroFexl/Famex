const kernel = @import("kernel");
const mm = kernel.mm;
const vmm = mm.vmm;
const mem = mm.memory;
const log = kernel.util.log;
const cpu = @import("arch").cpu;

pub const Process = struct {
    addr_space : vmm.VmSpace,
};

pub const kernel_process : Process = undefined;

/// For static percpu allocations, this is used to get the actual index relative to the percpu region
pub var PER_CPU_LINKER_OFFSET : mem.Vaddr = undefined;

/// This gets the offset that dynamic allocations start at
pub var PER_CPU_STARTING_OFFSET : usize = undefined;

fn getLocalPercpu(comptime T: type, addr : u64) *T {
    return @ptrFromInt(@intFromPtr(cpu.getPerCpu()) + addr);
}

fn getGlobalPercpu(comptime T: type, cpu_num : u8, addr : u64) *T {
    return @ptrFromInt(mem.PER_CPU_DATA.val + mem.PER_CPU_DATA_SIZE * cpu_num + addr);
}

/// Static per-cpu allocation that is resolved at comptime
/// Use as "const per_cpu = PerCpuStat(u64);" or whatever type you need.
pub fn PerCpuStat(comptime T: type) type {
    return struct {
        const data: T linksection(".percpu") = undefined;

        pub fn getLocal() *T {
            return getLocalPercpu(T, @intFromPtr(&data) - PER_CPU_LINKER_OFFSET.val);
        }

        pub fn getGlobal(cpu_num : anytype) *T {
            return getGlobalPercpu(T, @intCast(cpu_num), @intFromPtr(&data) - PER_CPU_LINKER_OFFSET.val);
        }
    };
}

/// Dynamic per-cpu allocations that are created at runtime
pub fn PerCpuDyn(comptime T: type) type {
    return struct {
        data : ?*T = null,

        pub fn alloc(self : *@This()) void {
            log.apanic(self.data != null, "pm: A percpu variable attempted to allocate when already allocated!\n", .{});
        }

        pub fn free(self : *@This()) void {
            log.apanic(self.data == null, "pm: A percpu variable attempted to free when it was already free!\n", .{});
        }

        pub fn getLocal(self : *@This()) *T {
            return getLocalPercpu(T, @intFromPtr(self.data.?));
        }

        pub fn getGlobal(self : *@This(), cpu_num : u8) *T {
            return getGlobalPercpu(T, cpu_num, @intFromPtr(self.data.?));
        }
    };
}

pub export fn inKmode(state : *cpu.CpuState) callconv(.c) bool {
    return state.getStack() >= mem.KERNEL_MEMORY.val;
}
