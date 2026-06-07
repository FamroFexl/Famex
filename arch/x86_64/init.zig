const kernel = @import("kernel");
const mm = kernel.mm;
const log = kernel.util.log;
const print = log.print;
const bin = kernel.util.binary;

const lib = @import("lib");
const cpuid = lib.cpuid_db;
const limine = lib.limine;

const api = @import("arch_api");

const cpu = @import("cpu.zig");
const timers = @import("timers.zig");
const reg = @import("registers.zig");
const PatTypes = reg.PatTypes;

pub var paging_mode_request = limine.LiminePagingModeRequest {
    .mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
    .min_mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
    .max_mode = limine.LIMINE_PAGING_MODE_X86_64_4LVL,
};

pub var mp_request = limine.LimineMpRequest {
    .flags = limine.LIMINE_MP_REQUEST_X86_64_X2APIC,
    .response = undefined,
};

const PAT : reg.Pat = .{
    PatTypes.UNCACHEABLE,
    PatTypes.WRITE_COMBINING,
    PatTypes.UNCACHEABLE,
    PatTypes.UNCACHEABLE,
    PatTypes.WRITE_THROUGH,
    PatTypes.WRITE_PROTECTED,
    PatTypes.WRITE_BACK,
    PatTypes.UNCACHED,
};

// Make sure the CPU is in the state it should be (as limine reports)
fn validate_cpu_state() void {
    if (cpu.leaf_0x81.edx.nx == 1) {
        const efer = reg.get_msr(reg.Msrs.EFER);
        log.apanic(efer.nxe == 0, "arch: No Execute Disable bit isn't enabled!\n", .{});
    }

    log.apanic(paging_mode_request.response.mode != limine.LIMINE_PAGING_MODE_X86_64_4LVL, "arch: Paging Mode isn't 4 level!\n", .{});

    if (cpu.leaf_0x1.ecx.x2apic) {
        const apic : reg.ApicBase = reg.get_msr(reg.Msrs.APIC_BASE);
        log.apanic(apic.x2apic == 0, "arch: X2APIC isn't enabled!\n", .{});
    }
}

fn ensure_features() void {
    print("arch: Ensuring CPU meets minimum requirements\n", .{});

    log.apanic(cpu.leaf_0x0.eax.max_std_leaf < 8, "arch: CPUID max leaf isn't large enough!\n", .{});

    const intel : bool = cpu.VENDOR == cpu.cpu_vendor.INTEL;

    timers.TSC_INVARIANT = cpu.leaf_0x87.edx.constant_tsc == 1;

    if(intel) {
        timers.TSC_DEADLINE = cpu.leaf_0x1.ecx.tsc_deadline_timer == 1;

        // We support Nehalem-Clarksfield and later Intel CPUs (because of VT-d support)
        // (we may support Westmere and later only for guaranteed huge page and PCID support)
        log.apanic(cpu.leaf_0x1.eax.base_family_id < 0x1A,"arch: Intel CPU model isn't supported!\n", .{});

        log.apanic(cpu.leaf_0x1.ecx.vmx == 0, "arch: Intel VMX extensions are required!\n", .{});

        if (cpu.leaf_0x1.edx.pse == 1)
            bin.set_if_larger(u8, &api.cpu.FEATURES.MAX_PAGE_SIZE, 1);
    }
    else {
        // We support Bulldozer Family 15h and later AMD CPUs (because of AMD-Vi support)
        log.apanic(cpu.leaf_0x81.eax.e_base_family < 0x15, "arch: AMD CPU model isn't supported!\n", .{});

        // We need SVM for AMD-Vi (IOMMU)
        log.apanic(cpu.leaf_0x81.ecx.svm == 0, "arch: AMD SVM extensions are required!\n", .{});

        if (cpu.leaf_0x81.edx.e_pse == 1)
            bin.set_if_larger(u8, &api.cpu.FEATURES.MAX_PAGE_SIZE, 1);

    }

    if (cpu.leaf_0x81.edx.page1gb == 1)
        bin.set_if_larger(u8, &api.cpu.FEATURES.MAX_PAGE_SIZE, 2);

    api.cpu.FEATURES.EXECUTE_BIT = cpu.leaf_0x81.edx.nx == 1;
    api.cpu.FEATURES.READ_BIT = false;
}

pub fn init() void {
    cpu.init_cpuid();

    // Ensure the CPU is supported with the required features
    ensure_features();

    api.cpu.FEATURES.PHYS_ADDR_BITS = @intCast(cpu.leaf_0x88.eax.phys_addr_bits);
    api.cpu.FEATURES.VIRT_ADDR_BITS = @intCast(cpu.leaf_0x88.eax.virt_addr_bits);
    api.cpu.FEATURES.PAGE_TABLE_LEVELS = 4;

    api.cpu.FEATURES.NUM_CPU_CORES = mp_request.response.x86.cpu_count;

    mm.memory.setup_mem_mgmt();
}