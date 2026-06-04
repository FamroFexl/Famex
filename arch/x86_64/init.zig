const kernel = @import("kernel");
const mm = kernel.mm;
const log = kernel.util.log;
const print = log.print;
const bin = kernel.util.binary;

const cpuid = @import("lib").cpuid_db;

const export_cpu = @import("arch_export").cpu;
const cpu = @import("cpu.zig");
const timers = @import("timers.zig");

fn ensure_features() void {
    print("arch: Ensuring CPU meets minimum requirements\n", .{});

    const leaf_0x0 : cpuid.leaf_0x0_0 = cpu.cpuid(cpuid.leaf_0x0_0, 0x0, 0);
    log.apanic(leaf_0x0.eax.max_std_leaf < 8, "arch: CPUID max leaf isn't large enough!\n", .{});

    cpu.set_cpu_vendor(leaf_0x0);
    const intel : bool = cpu.VENDOR == cpu.cpu_vendor.INTEL;

    const leaf_0x1 : cpuid.leaf_0x1_0 = cpu.cpuid(cpuid.leaf_0x1_0, 0x1, 0);
    if(intel) {
        timers.TSC_DEADLINE = leaf_0x1.ecx.tsc_deadline_timer == 1;
    }

    const leaf_0x87 : cpuid.leaf_0x80000007_0 = cpu.cpuid(cpuid.leaf_0x80000007_0, 0x80000007, 0);
    timers.TSC_INVARIANT = leaf_0x87.edx.constant_tsc == 1;

    const leaf_0x81 : cpuid.leaf_0x80000001_0 = cpu.cpuid(cpuid.leaf_0x80000001_0, 0x80000001, 0);

    if(intel) {
        // We support Nehalem-Clarksfield and later Intel CPUs (because of VT-d support)
        // (we may support Westmere and later only for guaranteed huge page and PCID support)
        log.apanic(leaf_0x1.eax.base_family_id < 0x1A,"arch: Intel CPU model isn't supported!\n", .{});

        log.apanic(leaf_0x1.ecx.vmx == 0, "arch: Intel VMX extensions are required!\n", .{});

        if (leaf_0x1.edx.pse == 1)
            bin.set_if_larger(u8, &export_cpu.FEATURES.max_page_size, 1);
    }
    else {
        // We support Bulldozer Family 15h and later AMD CPUs (because of AMD-Vi support)
        log.apanic(leaf_0x81.eax.e_base_family < 0x15, "arch: AMD CPU model isn't supported!\n", .{});

        // We need SVM for AMD-Vi (IOMMU)
        log.apanic(leaf_0x81.ecx.svm == 0, "arch: AMD SVM extensions are required!\n", .{});

        if (leaf_0x81.edx.e_pse == 1)
            bin.set_if_larger(u8, &export_cpu.FEATURES.max_page_size, 1);

    }

    if (leaf_0x81.edx.page1gb == 1)
        bin.set_if_larger(u8, &export_cpu.FEATURES.max_page_size, 2);

    export_cpu.FEATURES.execute_bit = leaf_0x81.edx.nx == 1;
    export_cpu.FEATURES.read_bit = false;
}

pub fn init() void {
    // Ensure the CPU is supported with the required features
    ensure_features();

    const leaf_0x80000008_0 = cpu.cpuid(cpuid.leaf_0x80000008_0, 0x80000008, 0);

    mm.memory.PHYS_ADDR_BITS = @intCast(leaf_0x80000008_0.eax.phys_addr_bits);
    mm.memory.VIRT_ADDR_BITS = @intCast(leaf_0x80000008_0.eax.virt_addr_bits);
    mm.paging.PT_LEVELS = 4;

    mm.memory.setup_mem_mgmt();
}