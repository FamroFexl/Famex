///  AMD:     "AuthenticAMD"
const signature_AMD_ebx : u32 =  0x68747541;
const signature_AMD_edx : u32 = 0x69746e65;
const signature_AMD_ecx  : u32 = 0x444d4163;
/// INTEL:   "GenuineIntel"
const signature_INTEL_ebx : u32 = 0x756e6547;
const signature_INTEL_edx : u32 = 0x49656e69;
const signature_INTEL_ecx : u32 = 0x6c65746e;

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