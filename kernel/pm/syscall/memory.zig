const kernel = @import("kernel");
const cast = kernel.cast;
const bin = kernel.bin;
const types = kernel.types;

const vmm = kernel.mm.vmm;

const arch = @import("arch");
const cpu = arch.cpu;

const SysRet = @import("syscall.zig").SysRet;

const posix = @import("lib").posix;
const MapleTree = @import("lib").linux.MapleTree;

// pub fn mprotect(state : *cpu.CpuState) SysRet {
//     const addr = cast.toPtr(*allowzero anyopaque, state.getArgSys(0).*);
//     const len = state.getArgSys(1).*;
//     const prot = bin.convert(posix.mman.PROT, state.getArgSys(2).*);
//
//     if (@intFromPtr(addr) % types.SIZE_4KB != 0)
//         return .fail(.EINVAL);
//
//     if (len % types.SIZE_4KB != 0)
//         return .fail(.ENOMEM);
//
//     if (!arch.mm.validAccess(prot.READ, prot.WRITE, prot.EXEC))
//         return .fail(.ENOTSUP);
//
//     const process = kernel.cThread().owner;
//
//     var maState = MapleTree.MaState.create(&process.addrSpace, @intFromPtr(addr), @intFromPtr(addr) + len - 1);
//     maState.lock();
//     defer maState.unlock();
//
//     const out = maState.emptyArea(&maState, @intFromPtr(addr), @intFromPtr(addr) + len - 1, 1);
//
//     // Area isn't full
//     if (out != 0)
//         return .fail(.ENOMEM);
//
//     var area = cast.toPtr(*kernel.mm.vmm.VmArea, process.addrSpace.tree.load(@intFromPtr(addr)).?);
//     while (are)
// }

// pub fn execve(state : *cpu.CpuState) SysRet {
//     const path = cast.toPtr([*:0]allowzero const u8, state.getArgSys(0).*);
//     const argv = cast.toPtr([*:null]allowzero [*:0]allowzero const u8, state.getArgSys(1).*);
//     const envp = cast.toPtr([*:null]allowzero [*:0]allowzero const u8, state.getArgSys(2).*);
//
// }

pub fn mmap(state : *cpu.CpuState) SysRet {
    const addr = cast.toPtr(*allowzero anyopaque, state.getArgSys(0).*);
    const len = state.getArgSys(1).*;
    const prot : posix.mman.PROT = @bitCast(@as(u32, @truncate(state.getArgSys(2).*)));
    const flags : posix.mman.MAP = @bitCast(@as(u32, @truncate(state.getArgSys(3).*)));
    const fildes : i32 = @bitCast(@as(u32, @truncate(state.getArgSys(4).*)));
    const off : posix.types.off_t = state.getArgSys(5).*;

    var addrSpace = kernel.cThread().owner.addrSpace;

    if (len == 0)
        return .fail(.EINVAL);

    if (flags.PRIVATE and flags.SHARED)
        return .fail(.ENOTSUP);

    if (!arch.mm.validAccess(prot.READ, prot.WRITE, prot.EXEC))
        return .fail(.ENOTSUP);

    if (flags.ANONYMOUS and fildes == -1 and off == 0) {
        const lenAligned = bin.alignUp(len, types.SIZE_4KB) + types.SIZE_4KB;
        const area = kernel.pmalloc(vmm.VmArea);

        const start = addrSpace.tree.allocRange(
            lenAligned,
            addrSpace.mmapBase.val,
            bin.alignDown(bin.alignDown(state.rsp, types.SIZE_4KB) - kernel.config.USER_STACK_GUARD_GAP, types.SIZE_4KB),
            area);

        const startAligned = bin.alignUp(start, types.SIZE_4KB);
        const endAligned = startAligned + lenAligned;

        addrSpace.mmapBase.val = endAligned;

        area.* = .{
            .start = .asVirt(startAligned),
            .end = .asVirt(endAligned),
            .areaType = .USER_HEAP,
            .flags = .{
                .read = prot.READ,
                .write = prot.WRITE,
                .exec = prot.EXEC,
            }
        };

        return .ok(startAligned);
    }

    if (flags.FIXED)
        return .ok(@intFromPtr(addr));

    return .ok(0);
}

// pub fn munmap(state : *cpu.CpuState) SysRet {
//     const addr = cast.toPtr(*anyopaque, state.getArgSys(0).*);
//     const len = state.getArgSys(1).*;
// }