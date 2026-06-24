const cpuid_db = @import("lib").cpuid_db;
const kernel = @import("kernel");
const proc = kernel.pm.process;

const api = @import("arch_api");
const log = kernel.util.log;

/// Pool for FP save state allocations
pub var FP_SAVE_POOL : kernel.mm.slub_alloc.SlubPool = undefined;
/// Used to initialize FP states for new threads
pub var FP_INIT : api.cpu.FpuState = undefined;
/// Use XSave if true, FXSave if false
pub var XSAVE_ON : bool = false;

pub const cpuId = proc.PerCpuStat(u8);

///  AMD:     "AuthenticAMD"
const signature_AMD_ebx : u32 =  0x68747541;
const signature_AMD_edx : u32 = 0x69746e65;
const signature_AMD_ecx  : u32 = 0x444d4163;
/// INTEL:   "GenuineIntel"
const signature_INTEL_ebx : u32 = 0x756e6547;
const signature_INTEL_edx : u32 = 0x49656e69;
const signature_INTEL_ecx : u32 = 0x6c65746e;

pub const CpuVendor = enum {
    INTEL,
    AMD
};

pub var VENDOR : CpuVendor = undefined;

pub var leaf_0x0 : cpuid_db.leaf_0x0_0 = undefined;
pub var leaf_0x1 : cpuid_db.leaf_0x1_0 = undefined;
pub var leaf_0x81 : cpuid_db.leaf_0x80000001_0 = undefined;
pub var leaf_0x87 : cpuid_db.leaf_0x80000007_0 = undefined;
pub var leaf_0x88 : cpuid_db.leaf_0x80000008_0 = undefined;

pub fn setCpuVendor() void {
    if (leaf_0x0.ebx.cpu_vendorid_0 == signature_INTEL_ebx and
        leaf_0x0.edx.cpu_vendorid_1 == signature_INTEL_edx and
        leaf_0x0.ecx.cpu_vendorid_2 == signature_INTEL_ecx) {
        VENDOR = CpuVendor.INTEL;
    }
    else if (
    leaf_0x0.ebx.cpu_vendorid_0 == signature_AMD_ebx and
        leaf_0x0.edx.cpu_vendorid_1 == signature_AMD_edx and
        leaf_0x0.ecx.cpu_vendorid_2 == signature_AMD_ecx) {
        VENDOR = CpuVendor.AMD;
    }
    else {
        log.panic("arch: CPU Manufacturer isn't AMD or Intel!\n", .{});
    }
}

/// CPUID in a convenient form
///
/// T:          Leaf type to interface into
/// leaf:       Main numeral indicating the specified information to retrieve
/// subleaf:    Optional specifier for more precise CPUID instructions
pub fn cpuid(comptime T: type, leaf : u32, subleaf : u32) T {
    var eax : u32 = undefined;
    var ebx : u32 = undefined;
    var ecx : u32 = undefined;
    var edx : u32 = undefined;

    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx)
        : [leaf] "{eax}" (leaf),
          [count] "{ecx}" (subleaf)
    );

    return .{
        .eax = @bitCast(eax),
        .ebx = @bitCast(ebx),
        .ecx = @bitCast(ecx),
        .edx = @bitCast(edx)
    };
}

pub fn initCpuid() void {
    leaf_0x0 = cpuid(cpuid_db.leaf_0x0_0, 0x0, 0);
    leaf_0x1 = cpuid(cpuid_db.leaf_0x1_0, 0x1, 0);
    leaf_0x81 = cpuid(cpuid_db.leaf_0x80000001_0, 0x80000001, 0);
    leaf_0x87 = cpuid(cpuid_db.leaf_0x80000007_0, 0x80000007, 0);
    leaf_0x88 = cpuid(cpuid_db.leaf_0x80000008_0, 0x80000008, 0);

    setCpuVendor();
}