const kernel = @import("kernel");
const mm = kernel.mm;
const vmm = mm.vmm;
const mem = mm.memory;
const log = kernel.util.log;
const arch_cpu = @import("arch").cpu;

pub const Process = struct {
    addr_space : vmm.VmSpace,
};

pub const kernel_process : Process = undefined;

var PER_CPU_LINKER_OFFSET : mem.Vaddr = undefined;

fn get_local_percpu(comptime T: type, addr : u64) *T {
    return @ptrFromInt(@intFromPtr(arch_cpu.get_per_cpu()) + addr - PER_CPU_LINKER_OFFSET.val);
}

fn get_global_percpu(comptime T: type, cpu : u8, addr : u64) *T {
    return @ptrFromInt(mem.PER_CPU_DATA.val + mem.PER_CPU_DATA_SIZE * cpu + addr - PER_CPU_LINKER_OFFSET.val);
}

/// Static per-cpu allocation that is resolved at comptime
/// Use as "const per_cpu = PerCpuStat(u64);" or whatever type you need.
pub fn PerCpuStat(comptime T: type) type {
    return struct {
        const data: T linksection(".percpu") = undefined;

        pub fn get_local() *T {
            return get_local_percpu(T, @intFromPtr(&data));
        }

        pub fn get_global(cpu : anytype) *T {
            return get_global_percpu(T, @intCast(cpu), @intFromPtr(&data));
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

        pub fn get_local(self : *@This()) *T {
            return get_local_percpu(T, self.data);
        }

        pub fn get_global(self : *@This(), cpu : u8) *T {
            return get_global_percpu(T, cpu, self.data);
        }
    };
}

pub export fn in_kmode(state : *arch_cpu.CpuState) callconv(.c) bool {
    return state.get_stack() >= mem.KERNEL_MEMORY.val;
}
