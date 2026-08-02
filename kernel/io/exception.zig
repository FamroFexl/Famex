const kernel = @import("kernel");
const cast = kernel.cast;
const bin = kernel.bin;
const types = kernel.types;

const irq = @import("irq.zig");
const paging = kernel.mm.paging;

const lib = @import("lib");

const arch = @import("arch");

pub const ExceptionType = enum {
    MATH_ERROR,
    NO_FPU_STATE,

    PAGE_FAULT,
    ALIGN_FAULT,
    BAD_ADDR,

    TRAP,           // Debug

    BAD_OPCODE,
    GENERAL_FAULT,
};

pub const ExceptionData = union {
    pfault : struct {
        addr : kernel.Vaddr,
        present : bool,
        access : enum { READ, WRITE, EXECUTE }
    },
    mathFault : lib.posix.signal.SigCode,
};

/// Page fault handler lookup table
var pfaultLUT : []struct {fault : u64, handler : u64} = undefined;

pub fn pageFault(data : *ExceptionData, state : *kernel.CpuState) void {
    const addr = data.pfault.addr;
    const vmSpace = &kernel.cThread().owner.addrSpace;

    const area = cast.toPtr(*kernel.mm.vmm.VmArea, vmSpace.tree.find(addr.val, addr.val) orelse {
        const uThread = kernel.cThread().container().uThread;
        const uStack = uThread.uStack;

        // Stack fault
        if (uThread.uStack.start.val - kernel.config.USER_STACK_GUARD_GAP <= data.pfault.addr.val) {
            const start = bin.alignDown(data.pfault.addr.val, types.SIZE_4KB);
            const end = uStack.start.val;
            uStack.start.val = start;

            _ = uThread.base.owner.addrSpace.tree.storeRange(start, uThread.uStack.end.val, uThread.uStack);

            // TODO fix pfe state iterator off by 4kb at end
            var pfeState = kernel.PfeState(.MAP).create(&uThread.base.owner.addrSpace, .asVirt(start), .asVirt(end + types.SIZE_4KB), .LEVEL_4KB);
            while (pfeState.next()) |pfe| {
                pfe.* = paging.PFE_DEFAULTS[0];
                pfe.setUser(0, true);
                pfe.setExec(0, uStack.flags.exec);

                pfe.setEntry(0, kernel.allocPage4k());
            }

            return;
        }

        // User copy fault
        for (pfaultLUT) |lut| {
            if (state.getPc() == lut.fault) {
                state.setPc(lut.handler);
                return;
            }
        }

        if (state.inKmode())
            @panic("Page fault in kernel mode!");

        // Kill thread
        @panic("thread kill!");

        //return;
    });


    // Invalid access fault
    if ((!area.flags.read and data.pfault.access == .READ) or
        (!area.flags.write and data.pfault.access == .WRITE) or
        (!area.flags.exec and data.pfault.access == .EXECUTE)
    ) {
        // User copy fault
        for (pfaultLUT) |lut| {
            if (state.getPc() == lut.fault) {
                state.setPc(lut.handler);
                return;
            }
        }

        if (state.inKmode())
            @panic("Page fault in kernel mode!");

        @panic("thread kill!");
        // Kill thread
    }

    const start = bin.alignDown(addr.val, types.SIZE_4KB);
    const end = bin.alignUp(addr.val, types.SIZE_4KB);

    var pfeState = kernel.PfeState(.MAP).create(vmSpace, .asVirt(start), .asVirt(end), .LEVEL_4KB);
    const pfe = pfeState.next().?;

    var pageFlush = false;

    if (!pfe.getEmpty(0)) {
        // Permissions update fault
        if (pfe.getPresent(0)) {
            // Zero page
            if (pfe.getEntry(0).val == kernel.mm.vmm.EMPTY_PAGE.getEntry(0).val) {
            }
            else if (area.flags.read and !pfe.getRead(0)) {
                pfe.setRead(0, true);
            }
            else if (area.flags.write and !pfe.getWrite(0)) {
                pfe.setWrite(0, true);
            }
            else if (area.flags.exec and !pfe.getExec(0)) {
                pfe.setExec(0, true);
            }

            pageFlush = true;
        }
        // Swapped page fault
        else {

        }
    }

    // Demand paging fault
    if (area.areaType == .USER_TEXT or area.areaType == .USER_BSS) {
        // Other areas may exist in the same page, we have to OR their permissions
        if (area.start.val > start or area.end.val < end) {
            var read = false;
            var write = false;
            var exec = false;

            pfe.* = paging.PFE_DEFAULTS[0];
            pfe.setEntry(0, kernel.allocPage4k());

            // TODO mas.next doesn't work
            var mas = lib.linux.MapleTree.MaState.create(&vmSpace.tree, start - 1, end - 1);
            mas.lock();

            //while (mas.next(end - 1)) |link| {
            while (mas.find(end - 1)) |link| {
                const newArea = cast.toPtr(*kernel.mm.vmm.VmArea, link);
                read = newArea.flags.read or read;
                write = newArea.flags.write or write;
                exec = newArea.flags.exec or exec;

                const newStart = bin.max(newArea.start.val, start);
                const newEnd = bin.min(newArea.end.val, end);

                if (newArea.areaType == .USER_BSS) {
                    kernel.memset(@ptrFromInt(newStart), newEnd - newStart, 0);
                }
                else {
                    const page = kernel.Vaddr.asVirt(newArea.file + newArea.fileOffset + newStart - newArea.start.val);
                    kernel.memcpy(@ptrFromInt(newStart), page.ptr(), newEnd - newStart);
                }
            }

            mas.unlock();

            pfe.setUser(0, true);
            pfe.setRead(0, read);
            pfe.setWrite(0, write);
            pfe.setExec(0, exec);
        }
        else {
            if (area.areaType == .USER_BSS) {
                if (data.pfault.access == .READ) {
                    pfe.* = kernel.mm.vmm.EMPTY_PAGE;
                }
                else {
                    pfe.* = paging.PFE_DEFAULTS[0];
                    pfe.setUser(0, true);
                    pfe.setRead(0, area.flags.read);
                    pfe.setWrite(0, area.flags.write);
                    pfe.setExec(0, area.flags.exec);

                    pfe.setEntry(0, kernel.zallocPage4k());
                }
            }
            else {
                pfe.* = paging.PFE_DEFAULTS[0];
                pfe.setUser(0, true);
                pfe.setRead(0, area.flags.read);
                pfe.setWrite(0, area.flags.write);
                pfe.setExec(0, area.flags.exec);

                const newPage = kernel.allocPage4k();

                const page = kernel.Vaddr.asVirt(area.file + area.fileOffset + start - area.start.val);

                kernel.memcpy(newPage.toVirt().ptr(), page.ptr(), types.SIZE_4KB);

                pfe.setEntry(0, newPage);
            }
        }
    }
    // Demand paging fault
    else if (area.areaType == .USER_HEAP) {
        if (data.pfault.access == .READ) {
            // Set to read-only zeroed page
            pfe.* = kernel.mm.vmm.EMPTY_PAGE;
        }
        else {
            pfe.* = paging.PFE_DEFAULTS[0];
            pfe.setUser(0, true);
            pfe.setRead(0, area.flags.read);
            pfe.setWrite(0, area.flags.write);
            pfe.setExec(0, area.flags.exec);

            pfe.setEntry(0, kernel.zallocPage4k());
        }
    }

    // File Paging

    // Flush the page if needed
    if (pageFlush) {
        kernel.SmpCall.create(
            kernel.cThread().owner.addrSpace.cpuMask,
            false,
            null,
            .{
                    .func = kernel.mm.paging.flushPages,
                    .args = .{start, end, 0, 0, 0, 0},
            }
        );
    }
}

pub fn mathFault(data : *ExceptionData, state : *kernel.CpuState) void {
    if (state.inKmode())
        @panic("Math fault in kmode!");

    const thread = kernel.cThread();

    kernel.pm.signal.sigSend(.THREAD, thread, .{
        .si_signo = .SIGFPE,
        .si_code = data.mathFault,
        .si_addr = @ptrFromInt(state.getPc()),
    }) catch undefined;
}

/// Allocate an fpu state if the thread tries to use fpu instructions
pub fn noFpuFault() void {
    kernel.cThread().fpuContext = arch.cpu.FpuState.alloc();
}

pub fn handler(irqNum : u64, data : *ExceptionData, state : *kernel.CpuState) void {
    switch (arch.irq.getExceptionType(irqNum)) {
        .PAGE_FAULT => pageFault(data, state),
        .MATH_ERROR => mathFault(data, state),
        .NO_FPU_STATE => noFpuFault(),
        else => @panic("unhandled handler!"),
    }
}

pub fn setup() void {
    const elf_hdr = cast.toPtr(*lib.elf.ElfHdr, kernel.Limine.executable_file_request.response.*.executable_file.address);
    const shdr = elf_hdr.getShdrByName(".excp_tbl") orelse @panic("Couldn't retrieve the exception table!");

    pfaultLUT.ptr = @ptrFromInt(shdr.addr);
    pfaultLUT.len = shdr.size / 8;
}