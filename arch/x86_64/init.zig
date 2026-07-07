const kernel = @import("kernel");
const cast = kernel.cast;
const log = kernel.util.log;
const print = log.print;
const bin = kernel.util.binary;
const types = kernel.util.types;
const acpi = kernel.io.acpi;

const lib = @import("lib");
const cpuid = lib.cpuid_db;
const limine = lib.limine;

const api = @import("arch_api");

const cpu = @import("cpu.zig");
const timers = @import("timers.zig");
const reg = @import("registers.zig");
const irq = @import("irq.zig");
const apic = @import("apic.zig");

pub var paging_mode_request = limine.LiminePagingModeRequest {
    .mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
    .min_mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
    .max_mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
};

pub var smp_request = limine.LimineMpRequest {
    .flags = limine.LIMINE_MP_REQUEST_X86_64_X2APIC,
    .response = undefined,
};

const PAT : reg.Pat.Layout = .{
    .pa0 = .UNCACHEABLE,
    .pa1 = .WRITE_COMBINING,
    .pa2 = .UNCACHEABLE,
    .pa3 = .UNCACHEABLE,
    .pa4 = .WRITE_THROUGH,
    .pa5 = .WRITE_PROTECTED,
    .pa6 = .WRITE_BACK,
    .pa7 = .UNCACHED,
};

var GDTR : reg.Gdtr = undefined;
var IDTR : reg.Idtr = undefined;

// Make sure the CPU is in the state it should be (as limine reports)
fn validateCpuState() void {
    if (cpu.leaf_0x81.nx == 1) {
        const efer = reg.Efer.get();
        log.apanic(!efer.nxe, "arch: No Execute Disable bit isn't enabled!\n", .{});
    }

    log.apanic(paging_mode_request.response.mode != limine.LIMINE_PAGING_MODE_X86_64_4LVL, "arch: Paging Mode isn't 4 level!\n", .{});

    if (cpu.leaf_0x1.x2apic == 1) {
        log.apanic(!reg.ApicBase.get().x2apic, "arch: X2APIC isn't enabled!\n", .{});
    }
}

fn ensureFeatures() void {
    print("arch: Ensuring CPU meets minimum requirements\n", .{});

    const intel : bool = cpu.VENDOR == cpu.CpuVendor.INTEL;

    if(intel) {
        // We support Nehalem-Clarksfield and later Intel CPUs (because of VT-d support)
        // (we may support Westmere and later only for guaranteed huge page and PCID support)
        if (cpu.leaf_0x1.base_family_id < 0x06 and cpu.leaf_0x1.base_model < 0x1A) {
            log.panic("arch: Intel CPU model isn't supported!\n", .{});
        }

        //log.apanic(cpu.leaf_0x1.vmx == 0, "arch: Intel VMX extensions are required!\n", .{});

        if (cpu.leaf_0x1.pse == 1)
            bin.setIfLarger(u3, &api.cpu.FEATURES.MAX_PAGE_SIZE, 1);
    }
    else {
        // We support Bulldozer Family 15h and later AMD CPUs (because of AMD-Vi support)
        log.apanic(cpu.leaf_0x81.e_base_family < 0x15, "arch: AMD CPU model isn't supported!\n", .{});

        // We need SVM for AMD-Vi (IOMMU)
        //log.apanic(cpu.leaf_0x81.svm == 0, "arch: AMD SVM extensions are required!\n", .{});

        if (cpu.leaf_0x81.e_pse == 1)
            bin.setIfLarger(u3, &api.cpu.FEATURES.MAX_PAGE_SIZE, 1);

    }

    if (cpu.leaf_0x81.page1gb == 1)
        bin.setIfLarger(u3, &api.cpu.FEATURES.MAX_PAGE_SIZE, 2);

    api.cpu.FEATURES.EXECUTE_BIT = cpu.leaf_0x81.nx == 1;
    api.cpu.FEATURES.READ_BIT = false;
}

fn setupFp() void {
    print("arch: Setting up Floating Point (X87, SSE", .{});

    var cr4 = reg.Cr4.get();
    cr4.osfxcr = true;
    cr4.osxmmexcpt = true;

    // No XSave, just FXSave
    if (cpu.leaf_0x1.xsave == 0) {
        print(") Size 512\n", .{});
        reg.Cr4.set(cr4);
        cpu.FP_SAVE_POOL.init(512, 64, null);
        return;
    }

    cr4.osxsave = true;
    reg.Cr4.set(cr4);

    cpu.XSAVE_ON = true;

    var leaf = cpu.cpuid(cpuid.leaf_0xd_0, 0xd, 0);
    var xcr0 = reg.Xcr0.get();

    // Disable all the features we don't want and just enable X87, SSE, and AVX
    xcr0.x87 = true;    // This must be the case for any cpu we support
    if (leaf.xcr0_sse == 1)              xcr0.sse = true;
    if (leaf.xcr0_avx == 1)              {xcr0.avx = true; print(", AVX", .{});}
    if (leaf.xcr0_mpx_bndregs == 1)      xcr0.bndreg = false;
    if (leaf.xcr0_mpx_bndcsr == 1)       xcr0.bndcsr = false;
    if (leaf.xcr0_avx512_opmask == 1)    xcr0.opmask = false;
    if (leaf.xcr0_avx512_zmm_hi256 == 1) xcr0.zmm_hi256 = false;
    if (leaf.xcr0_avx512_hi16_zmm == 1)  xcr0.hi16_zmm = false;
    if (leaf.xcr0_pkru == 1)             xcr0.pkru = false;
    if (leaf.xcr0_tileconfig == 1)       xcr0.tilecfg = false;
    if (leaf.xcr0_tiledata == 1)         xcr0.tiledata = false;

    reg.Xcr0.set(xcr0);
    leaf = cpu.cpuid(cpuid.leaf_0xd_0, 0xd, 0);

    print(") Size {}\n", .{leaf.xsave_sz_xcr0_enabled});
    cpu.FP_SAVE_POOL.init(leaf.xsave_sz_xcr0_enabled, 64, null);

    cpu.FP_INIT.regs = cpu.FP_SAVE_POOL.alloc();
    reg.fpStateReset();
    cpu.FP_INIT.save();
}

/// Only one GDT for all cores
fn setupGdt() void {
    print("arch: Setting up Global Descriptor Table (GDT)\n", .{});

    const gdtSize = @sizeOf(reg.Gdtr.Layout) + api.cpu.FEATURES.NUM_CPU_CORES * @sizeOf(reg.TssDesc);
    const gdt= cast.toPtr(*reg.Gdtr.Layout, kernel.pmallocBytes(gdtSize));
    gdt.kmode_code = .{
        .seg_type = .SEG_CODE_ER,
        .priv_level = 0,
        .size = false,
        .code_seg = true,
    };

    gdt.kmode_data = .{
        .seg_type = .SEG_DATA_RW,
        .priv_level = 0,
        .size = true,
        .code_seg = false,
    };

    gdt.umode_code = .{
        .seg_type = .SEG_CODE_ER,
        .priv_level = 3,
        .size = false,
        .code_seg = true,
    };

    gdt.umode_data = .{
        .seg_type = .SEG_DATA_RW,
        .priv_level = 3,
        .size = true,
        .code_seg = false,
    };

    // Create per-core tss
    for (0..api.cpu.FEATURES.NUM_CPU_CORES) |i| {
        const tss_desc : *reg.TssDesc align(8) = &gdt.getTss()[i];
        const new_tss = kernel.pmalloc(reg.Tss);
        const tss = @intFromPtr(new_tss);
        tss_desc.* = .{
            .word1 = .{
                .address1 = @intCast(bin.getBits(24, 0, tss)),
                .address2 = @intCast(bin.getBits(8, 24, tss)),
            },
            .word2 = .{
                .address3 = @intCast(bin.getBits(32, 32, tss))
            }
        };

        // Assign interrupt stacks (stacks are at top of memory allocation)
        for (0..7) |j| {
            var ist_stack : u64 = undefined;
            // IST1 is used for general interrupts
            if (j == 0) {
                ist_stack = @intFromPtr(kernel.pmallocBytes(kernel.config.IRQ_STACK_SIZE)) + kernel.config.IRQ_STACK_SIZE;
            }
            // IST2 to IST7 Used for special interrupts (double faults, etc)
            else {
                ist_stack = @intFromPtr(kernel.pmallocBytes(types.SIZE_4KB)) + types.SIZE_4KB;
            }

            // Interrupt stacks should be 16-byte aligned (SysV ABI)
            new_tss.ist[j] = bin.alignDown(ist_stack, 16);
        }
    }

    GDTR.limit = @as(u16, @intCast(gdtSize)) - 1;
    GDTR.base = @intFromPtr(gdt);
}

/// One IDT for all cores
fn setupIdt() void {
    print("arch: Setting up Interrupt Descriptor Table (IDT)\n", .{});

    const idt = kernel.pmalloc(reg.Idtr.Layout);

    for (0..256) |i| {
        const func = irq.irqStubTable[i];

        idt.id_gate[i] = .{
            .word1 = .{
                .ist = 1,
                .offset1 = @intCast(bin.getBits(16, 0, func)),
                .offset2 = @intCast(bin.getBits(16, 16, func)),
            },
            .word2 = .{
                .offset3 = @intCast(bin.getBits(32, 32, func)),
            }
        };
    }

    // Intel idt[9], idt[15], and idt[22]->idt[31] irqs should never fire

    // All these interrupts have separate safe IST stacks
    idt.id_gate[@intFromEnum(irq.VecNum.DEBUG_XCP)].word1.ist       = 2;
    idt.id_gate[@intFromEnum(irq.VecNum.NON_MASK_IRQ)].word1.ist    = 3;
    idt.id_gate[@intFromEnum(irq.VecNum.DOUBLE_FAULT)].word1.ist    = 4;
    idt.id_gate[@intFromEnum(irq.VecNum.MACHINE_CHECK)].word1.ist   = 5;
    idt.id_gate[@intFromEnum(irq.VecNum.BAD_STACK_SEG)].word1.ist   = 6;
    idt.id_gate[@intFromEnum(irq.VecNum.GEN_PROTECT)].word1.ist     = 7;

    IDTR.limit = @sizeOf(reg.Idtr.Layout) - 1;
    IDTR.base = @intFromPtr(idt);
}

fn setupSyscalls() void {
    var efer = reg.Efer.get();
    efer.sce = true;
    reg.Efer.set(efer);

    // Set the syscall entry point (asm)
    reg.SyscallLStar.set(@intFromPtr(&kernel.pm.syscall.syscallHandler));

    // Set the RFLAGS mask on syscall entry
    var rflags : reg.Rflags = @bitCast(@as(u64, 0));

    // Flags to clear
    rflags.trap = true;
    rflags.iopl = 3;
    rflags.direction = true;
    rflags.irq_enable = true;

    reg.SyscallFMask.set(@bitCast(rflags));

    // Set the Kernel CS and SS segments on syscall entry and exit
    const kernel_cs : u64 = @offsetOf(reg.Gdtr.Layout, "kmode_code") << 32;
    const user_cs : u64 = @offsetOf(reg.Gdtr.Layout, "umode_code") << 48;
    reg.SyscallStar.set(kernel_cs | user_cs);
}

fn smpCpuInit(smp_info : *limine.LimineMpInfoX86) void {
    // Make sure the cpu is as limine reports
    validateCpuState();

    // The OS id for the processor
    const cpuId : u8 = @intCast(smp_info.extra_argument);
    cpu.cpuId.getLocal().* = cpuId;

    reg.Gdtr.set(&GDTR);

    reg.Idtr.set(&IDTR);

    reg.Tss.set(@intCast(@sizeOf(reg.Gdtr.Layout) + cpuId * @sizeOf(reg.TssDesc)));

    api.cpu.setPerCpu(@ptrFromInt(kernel.mm.memory.PER_CPU_DATA.val + kernel.mm.memory.PER_CPU_DATA_SIZE * cpuId));

    reg.Pat.set(PAT);

    setupSyscalls();

    if (smp_info.lapic_id != smp_request.response.x86.bsp_lapic_id) {
        apic.setupCore();

        // Go Idle
        api.cpu.idleEntry();
    }
}

fn setupSmp(init_bsp : bool) void {
    // Setup SMP cores
    for (0..smp_request.response.x86.cpu_count) |i| {
        // For now, cpu id mapping is from smp_request index to its lapic id
        const smp_info = smp_request.response.x86.cpus.x86[i];

        // The kernel-number for the core
        smp_info.extra_argument = i;

        // Is Bootstrap core (setup first)
        if (init_bsp) {
            if (smp_info.lapic_id == smp_request.response.x86.bsp_lapic_id) {
                smpCpuInit(smp_info);
                return;
            }
            continue;
        }

        // Causes the parked smp core to jump to smp_cpu_init
        @atomicStore(u64, @as(*u64, @ptrFromInt(smp_info.goto_address)), @intFromPtr(&smpCpuInit), .seq_cst);
    }
}

/// X86 linker entry point
pub export fn init() void {
    kernel.Limine.smp_request = &smp_request;

    cpu.initCpuid();

    // Ensure the CPU is supported with the required features
    ensureFeatures();

    api.cpu.FEATURES.PHYS_ADDR_BITS = @intCast(cpu.leaf_0x88.phys_addr_bits);
    api.cpu.FEATURES.VIRT_ADDR_BITS = @intCast(cpu.leaf_0x88.virt_addr_bits);
    api.cpu.FEATURES.PAGE_TABLE_LEVELS = 4;

    api.cpu.FEATURES.NUM_CPU_CORES = smp_request.response.x86.cpu_count;

    kernel.mm.memory.setup();

    setupFp();

    setupGdt();

    setupIdt();

    setupSmp(true);

    acpi.setupTables();

    apic.setup();

    apic.setupCore();

    timers.setup();
}