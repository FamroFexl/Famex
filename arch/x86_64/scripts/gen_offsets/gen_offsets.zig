const std = @import("std");
const reg = @import("reg");

var buf : [1024]u8 = undefined;
var writer : std.Io.File.Writer = undefined;

fn gen_pair(name : []const u8, num : anytype) void {
    writer.interface.print("#define {s} {d}\n", .{name, num}) catch return;
}

pub fn main(init: std.process.Init) !void {
    writer = std.Io.File.stdout().writerStreaming(init.io, &buf);

    gen_pair("KERNEL_GS_BASE", reg.KernelGsBase.addr);
    gen_pair("GS_BASE", reg.GsBase.addr);
    gen_pair("FS_BASE", reg.FsBase.addr);

    gen_pair("KMODE_CODE_OFST", @offsetOf(reg.Gdtr.Layout, "kmode_code"));
    gen_pair("KMODE_DATA_OFST", @offsetOf(reg.Gdtr.Layout, "kmode_data"));
    gen_pair("UMODE_CODE_OFST", @offsetOf(reg.Gdtr.Layout, "umode_code"));
    gen_pair("UMODE_DATA_OFST", @offsetOf(reg.Gdtr.Layout, "umode_data"));

    // CS and SS segment default descriptors
    gen_pair("CS_0", @offsetOf(reg.Gdtr.Layout, "kmode_code") | 0);
    gen_pair("SS_0", @offsetOf(reg.Gdtr.Layout, "kmode_data") | 0);
    gen_pair("CS_3", @offsetOf(reg.Gdtr.Layout, "umode_code") | 3);
    gen_pair("SS_3", @offsetOf(reg.Gdtr.Layout, "umode_code") | 3);

    gen_pair("INT_SFRAME_CS", @offsetOf(reg.IrqFrame, "cs"));
    gen_pair("INT_SFRAME_SS", @offsetOf(reg.IrqFrame, "ss"));
    gen_pair("INT_SFRAME_RIP", @offsetOf(reg.IrqFrame, "rip"));
    gen_pair("INT_SFRAME_RSP", @offsetOf(reg.IrqFrame, "rsp"));
    gen_pair("INT_SFRAME_RFLAGS", @offsetOf(reg.IrqFrame, "rflags"));

    gen_pair("CPU_STATE_SIZE", @sizeOf(reg.CpuState));

    gen_pair("RAX_OFST", @offsetOf(reg.CpuState, "rax"));
    gen_pair("RBX_OFST", @offsetOf(reg.CpuState, "rbx"));
    gen_pair("RCX_OFST", @offsetOf(reg.CpuState, "rcx"));
    gen_pair("RDX_OFST", @offsetOf(reg.CpuState, "rdx"));
    gen_pair("RSI_OFST", @offsetOf(reg.CpuState, "rsi"));
    gen_pair("RDI_OFST", @offsetOf(reg.CpuState, "rdi"));
    gen_pair("RBP_OFST", @offsetOf(reg.CpuState, "rbp"));
    gen_pair("R8_OFST", @offsetOf(reg.CpuState, "r8"));
    gen_pair("R9_OFST", @offsetOf(reg.CpuState, "r9"));
    gen_pair("R10_OFST", @offsetOf(reg.CpuState, "r10"));
    gen_pair("R11_OFST", @offsetOf(reg.CpuState, "r11"));
    gen_pair("R12_OFST", @offsetOf(reg.CpuState, "r12"));
    gen_pair("R13_OFST", @offsetOf(reg.CpuState, "r13"));
    gen_pair("R14_OFST", @offsetOf(reg.CpuState, "r14"));
    gen_pair("R15_OFST", @offsetOf(reg.CpuState, "r15"));

    gen_pair("RFLAGS_OFST", @offsetOf(reg.CpuState, "rflags"));
    gen_pair("RIP_OFST", @offsetOf(reg.CpuState, "rip"));
    gen_pair("RSP_OFST", @offsetOf(reg.CpuState, "rsp"));
    gen_pair("FS_BASE_OFST", @offsetOf(reg.CpuState, "fs_base"));
    gen_pair("GS_BASE_OFST", @offsetOf(reg.CpuState, "gs_base"));

    try writer.interface.flush();
}