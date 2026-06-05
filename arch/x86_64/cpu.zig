const cpuid_db = @import("lib").cpuid_db;
const log = @import("kernel").util.log;

///  AMD:     "AuthenticAMD"
const signature_AMD_ebx : u32 =  0x68747541;
const signature_AMD_edx : u32 = 0x69746e65;
const signature_AMD_ecx  : u32 = 0x444d4163;
/// INTEL:   "GenuineIntel"
const signature_INTEL_ebx : u32 = 0x756e6547;
const signature_INTEL_edx : u32 = 0x49656e69;
const signature_INTEL_ecx : u32 = 0x6c65746e;

pub const cpu_vendor = enum {
    INTEL,
    AMD
};

pub var VENDOR : cpu_vendor = undefined;

pub fn set_cpu_vendor(leaf_0x0_0 : cpuid_db.leaf_0x0_0) void {
    if (leaf_0x0_0.ebx.cpu_vendorid_0 == signature_INTEL_ebx and
        leaf_0x0_0.edx.cpu_vendorid_1 == signature_INTEL_edx and
        leaf_0x0_0.ecx.cpu_vendorid_2 == signature_INTEL_ecx) {
        VENDOR = cpu_vendor.INTEL;
    }
    else if (
    leaf_0x0_0.ebx.cpu_vendorid_0 == signature_AMD_ebx and
        leaf_0x0_0.edx.cpu_vendorid_1 == signature_AMD_edx and
        leaf_0x0_0.ecx.cpu_vendorid_2 == signature_AMD_ecx) {
        VENDOR = cpu_vendor.AMD;
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