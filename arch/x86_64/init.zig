const kernel = @import("kernel");
const mm = kernel.mm;
const log = kernel.util.log;
const print = log.print;
const bin = kernel.util.binary;
const types = kernel.util.types;

const lib = @import("lib");
const cpuid = lib.cpuid_db;
const limine = lib.limine;

const api = @import("arch_api");

const cpu = @import("cpu.zig");
const timers = @import("timers.zig");
const reg = @import("registers.zig");
const irq = @import("irq.zig");
const PatTypes = reg.PatTypes;

pub var paging_mode_request = limine.LiminePagingModeRequest {
    .mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
    .min_mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
    .max_mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
};

pub var smp_request = limine.LimineMpRequest {
    .flags = limine.LIMINE_MP_REQUEST_X86_64_X2APIC,
    .response = undefined,
};

const PAT : reg.Pat = .{
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
    if (cpu.leaf_0x81.edx.nx == 1) {
        const efer = reg.Efer.get();
        log.apanic(efer.nxe == 0, "arch: No Execute Disable bit isn't enabled!\n", .{});
    }

    log.apanic(paging_mode_request.response.mode != limine.LIMINE_PAGING_MODE_X86_64_4LVL, "arch: Paging Mode isn't 4 level!\n", .{});

    if (cpu.leaf_0x1.ecx.x2apic) {
        const apic : reg.ApicBase = @bitCast(reg.Msr.get(.APIC_BASE));
        log.apanic(apic.x2apic == 0, "arch: X2APIC isn't enabled!\n", .{});
    }
}

fn ensureFeatures() void {
    print("arch: Ensuring CPU meets minimum requirements\n", .{});

    log.apanic(cpu.leaf_0x0.eax.max_std_leaf < 8, "arch: CPUID max leaf isn't large enough!\n", .{});

    const intel : bool = cpu.VENDOR == cpu.CpuVendor.INTEL;

    timers.TSC_INVARIANT = cpu.leaf_0x87.edx.constant_tsc == 1;

    if(intel) {
        timers.TSC_DEADLINE = cpu.leaf_0x1.ecx.tsc_deadline_timer == 1;

        // We support Nehalem-Clarksfield and later Intel CPUs (because of VT-d support)
        // (we may support Westmere and later only for guaranteed huge page and PCID support)
        log.apanic(cpu.leaf_0x1.eax.base_family_id < 0x1A,"arch: Intel CPU model isn't supported!\n", .{});

        log.apanic(cpu.leaf_0x1.ecx.vmx == 0, "arch: Intel VMX extensions are required!\n", .{});

        if (cpu.leaf_0x1.edx.pse == 1)
            bin.setIfLarger(u3, &api.cpu.FEATURES.MAX_PAGE_SIZE, 1);
    }
    else {
        // We support Bulldozer Family 15h and later AMD CPUs (because of AMD-Vi support)
        log.apanic(cpu.leaf_0x81.eax.e_base_family < 0x15, "arch: AMD CPU model isn't supported!\n", .{});

        // We need SVM for AMD-Vi (IOMMU)
        log.apanic(cpu.leaf_0x81.ecx.svm == 0, "arch: AMD SVM extensions are required!\n", .{});

        if (cpu.leaf_0x81.edx.e_pse == 1)
            bin.setIfLarger(u3, &api.cpu.FEATURES.MAX_PAGE_SIZE, 1);

    }

    if (cpu.leaf_0x81.edx.page1gb == 1)
        bin.setIfLarger(u3, &api.cpu.FEATURES.MAX_PAGE_SIZE, 2);

    api.cpu.FEATURES.EXECUTE_BIT = cpu.leaf_0x81.edx.nx == 1;
    api.cpu.FEATURES.READ_BIT = false;
}

/// Only one GDT for all cores
fn setupGdt() void {
    print("\narch: Setting up Global Descriptor Table (GDT)\n", .{});

    const gdt= mm.memory.pmalloc(reg.Gdtr.Layout);
    gdt.kmode_code.seg_type = .SEG_CODE_ER;
    gdt.kmode_code.priv_level = 0;
    gdt.kmode_code.size = false;
    gdt.kmode_code.code_seg = true;

    gdt.kmode_data.seg_type = .SEG_DATA_RW;
    gdt.kmode_data.priv_level = 0;
    gdt.kmode_data.size = true;
    gdt.kmode_data.code_seg = false;

    gdt.umode_code.seg_type = .SEG_CODE_ER;
    gdt.umode_code.priv_level = 3;
    gdt.umode_code.size = false;
    gdt.umode_code.code_seg = true;

    gdt.umode_data.seg_type = .SEG_DATA_RW;
    gdt.umode_data.priv_level = 3;
    gdt.umode_data.size = true;
    gdt.kmode_data.code_seg = false;

    // Create per-core tss
    for (0..api.cpu.FEATURES.NUM_CPU_CORES) |i| {
        const tss_desc = &gdt.tss[i];
        const new_tss = mm.memory.pmalloc(reg.Tss);

        tss_desc.address1 = @intCast(bin.getBits(24, 0, @intFromPtr(tss_desc)));
        tss_desc.address2 = @intCast(bin.getBits(40, 24, @intFromPtr(tss_desc)));

        // Assign interrupt stacks (stacks are at top of memory allocation)
        for (0..7) |j| {
            var ist_stack : u64 = undefined;
            // IST1 is used for general interrupts
            if (j == 0) {
                ist_stack = @intFromPtr(mm.memory.pmallocBytes(kernel.config.IRQ_STACK_SIZE)) + kernel.config.IRQ_STACK_SIZE;
            }
            // IST2 to IST7 Used for special interrupts (double faults, etc)
            else {
                ist_stack = @intFromPtr(mm.memory.pmallocBytes(types.SIZE_4KB)) + types.SIZE_4KB;
            }

            // Interrupt stacks should be 16-byte aligned (SysV ABI)
            new_tss.ist[j] = bin.alignDown(ist_stack, 16);
        }
    }

    GDTR.base = @intFromPtr(gdt);
}

/// One IDT for all cores
fn setupIdt() void {
    print("\narch: Setting up Interrupt Descriptor Table (IDT)\n", .{});

    const idt = mm.memory.pmalloc(reg.Idtr.Layout);

    for (0..256) |i| {
        const func = irq.irqStubTable[i];
        const common_gate : reg.Idtr.IdtGateDesc = .{
            .ist = 1,
            .offset1 = @intCast(bin.getBits(16, 0, func)),
            .offset2 = @intCast(bin.getBits(48, 16, func)),
        };

        idt.id_gate[i] = common_gate;
    }

    // Intel idt[9], idt[15], and idt[22]->idt[31] irqs should never fire

    // All these interrupts have separate safe IST stacks
    idt.id_gate[@intFromEnum(irq.VecNum.DEBUG_XCP)].ist       = 2;
    idt.id_gate[@intFromEnum(irq.VecNum.NON_MASK_IRQ)].ist    = 3;
    idt.id_gate[@intFromEnum(irq.VecNum.DOUBLE_FAULT)].ist    = 4;
    idt.id_gate[@intFromEnum(irq.VecNum.MACHINE_CHECK)].ist   = 5;
    idt.id_gate[@intFromEnum(irq.VecNum.BAD_STACK_SEG)].ist   = 6;
    idt.id_gate[@intFromEnum(irq.VecNum.GEN_PROTECT)].ist     = 7;

    IDTR.base = @intFromPtr(idt);
}

fn setupSyscalls() void {
    var efer = reg.Efer.get();
    efer.sce = true;
    reg.Efer.set(efer);

    // Set the syscall entry point (asm)
    reg.Msr.set(.SYSCALL_LSTAR, kernel.pm.syscall.syscallHandler);

    // Set the RFLAGS mask on syscall entry
    var rflags : reg.Rflags = @bitCast(0);

    // Flags to clear
    rflags.trap = true;
    rflags.iopl = 3;
    rflags.direction = true;
    rflags.irq_enable = true;

    reg.Msr.set(.SYSCALL_FMASK, @bitCast(rflags));

    // Set the Kernel CS and SS segments on syscall entry and exit
    const kernel_cs : u64 = @offsetOf(reg.Gdtr.Layout, "kmode_code") << 32;
    const user_cs : u64 = @offsetOf(reg.Gdtr.Layout, "umode_code") << 48;
    reg.Msr.set(.SYSCALL_STAR, kernel_cs | user_cs);
}

pub export fn init() void {
    kernel.smp_request = &smp_request;

    cpu.initCpuid();

    // Ensure the CPU is supported with the required features
    ensureFeatures();

    api.cpu.FEATURES.PHYS_ADDR_BITS = @intCast(cpu.leaf_0x88.eax.phys_addr_bits);
    api.cpu.FEATURES.VIRT_ADDR_BITS = @intCast(cpu.leaf_0x88.eax.virt_addr_bits);
    api.cpu.FEATURES.PAGE_TABLE_LEVELS = 4;

    api.cpu.FEATURES.CACHELINE_SIZE = 64;

    api.cpu.FEATURES.NUM_CPU_CORES = smp_request.response.x86.cpu_count;

    mm.memory.setup();

    setupGdt();

    setupIdt();
}