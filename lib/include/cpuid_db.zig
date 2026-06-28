
/// Leaf 0x0
/// Maximum standard leaf number + CPU vendor string
pub const leaf_0x0_0 = packed struct(u128) {
    max_std_leaf: u32, // Highest standard CPUID leaf supported

    cpu_vendorid_0: u32, // CPU vendor ID string bytes 0 - 3

    cpu_vendorid_2: u32, // CPU vendor ID string bytes 8 - 11

    cpu_vendorid_1: u32, // CPU vendor ID string bytes 4 - 7
};

/// Leaf 0x1
///CPU FMS (Family/Model/Stepping) + standard feature flags
pub const leaf_0x1_0 = packed struct(u128) {
    stepping: u4, // Stepping ID
    base_model: u4, // Base CPU model ID
    base_family_id: u4, // Base CPU family ID
    cpu_type: u2, // CPU type
    reserved_0: u2, // Reserved
    ext_model: u4, // Extended CPU model ID
    ext_family: u8, // Extended CPU family ID
    reserved_1: u4, // Reserved

    brand_id: u8, // Brand index
    clflush_size: u8, // CLFLUSH instruction cache line size
    n_logical_cpu: u8, // Logical CPU count
    local_apic_id: u8, // Initial local APIC physical ID

    sse3: u1, // Streaming SIMD Extensions 3 (SSE3)
    pclmulqdq: u1, // PCLMULQDQ instruction support
    dtes64: u1, // 64-bit DS save area
    monitor: u1, // MONITOR/MWAIT support
    dscpl: u1, // CPL Qualified Debug Store
    vmx: u1, // Virtual Machine Extensions
    smx: u1, // Safer Mode Extensions
    est: u1, // Enhanced Intel SpeedStep
    tm2: u1, // Thermal Monitor 2
    ssse3: u1, // Supplemental SSE3
    cntxt_id: u1, // L1 Context ID
    sdbg: u1, // Silicon Debug
    fma: u1, // FMA extensions using YMM state
    cx16: u1, // CMPXCHG16B instruction support
    xtpr_update: u1, // xTPR Update Control
    pdcm: u1, // Perfmon and Debug Capability
    reserved_2: u1, // Reserved
    pcid: u1, // Process-context identifiers
    dca: u1, // Direct Cache Access
    sse4_1: u1, // SSE4.1
    sse4_2: u1, // SSE4.2
    x2apic: u1, // X2APIC support
    movbe: u1, // MOVBE instruction support
    popcnt: u1, // POPCNT instruction support
    tsc_deadline_timer: u1, // APIC timer one-shot operation
    aes: u1, // AES instructions
    xsave: u1, // XSAVE (and related instructions) support
    osxsave: u1, // XSAVE (and related instructions) are enabled by OS
    avx: u1, // AVX instructions support
    f16c: u1, // Half-precision floating-point conversion support
    rdrand: u1, // RDRAND instruction support
    guest_status: u1, // System is running as guest; (para-)virtualized system

    fpu: u1, // Floating-Point Unit on-chip (x87)
    vme: u1, // Virtual-8086 Mode Extensions
    de: u1, // Debugging Extensions
    pse: u1, // Page Size Extension
    tsc: u1, // Time Stamp Counter
    msr: u1, // Model-Specific Registers (RDMSR and WRMSR support)
    pae: u1, // Physical Address Extensions
    mce: u1, // Machine Check Exception
    cx8: u1, // CMPXCHG8B instruction
    apic: u1, // APIC on-chip
    reserved_3: u1, // Reserved
    sep: u1, // SYSENTER, SYSEXIT, and associated MSRs
    mtrr: u1, // Memory Type Range Registers
    pge: u1, // Page Global Extensions
    mca: u1, // Machine Check Architecture
    cmov: u1, // Conditional Move Instruction
    pat: u1, // Page Attribute Table
    pse36: u1, // Page Size Extension (36-bit)
    psn: u1, // Processor Serial Number
    clflush: u1, // CLFLUSH instruction
    reserved_4: u1, // Reserved
    ds: u1, // Debug Store
    acpi: u1, // Thermal monitor and clock control
    mmx: u1, // MMX instructions
    fxsr: u1, // FXSAVE and FXRSTOR instructions
    sse: u1, // SSE instructions
    sse2: u1, // SSE2 instructions
    selfsnoop: u1, // Self Snoop
    htt: u1, // Hyper-threading
    tm: u1, // Thermal Monitor
    ia64: u1, // Legacy IA-64 (Itanium) support bit, now reserved
    pbe: u1, // Pending Break Enable
};

pub const leaf_0xd_0 = packed struct(u128) {
    xcr0_x87: u1, // XCR0.X87 (bit 0) supported
    xcr0_sse: u1, // XCR0.SEE (bit 1) supported
    xcr0_avx: u1, // XCR0.AVX (bit 2) supported
    xcr0_mpx_bndregs: u1, // XCR0.BNDREGS (bit 3) supported (MPX BND0-BND3 registers)
    xcr0_mpx_bndcsr: u1, // XCR0.BNDCSR (bit 4) supported (MPX BNDCFGU/BNDSTATUS registers)
    xcr0_avx512_opmask: u1, // XCR0.OPMASK (bit 5) supported (AVX-512 k0-k7 registers)
    xcr0_avx512_zmm_hi256: u1, // XCR0.ZMM_Hi256 (bit 6) supported (AVX-512 ZMM0->ZMM7/15 registers)
    xcr0_avx512_hi16_zmm: u1, // XCR0.HI16_ZMM (bit 7) supported (AVX-512 ZMM16->ZMM31 registers)
    reserved_0: u1, // Reserved
    xcr0_pkru: u1, // XCR0.PKRU (bit 9) supported (XSAVE PKRU registers)
    reserved_1: u1, // Reserved
    xcr0_cet_u: u1, // XCR0.CET_U (bit 11) supported (CET user state)
    xcr0_cet_s: u1, // XCR0.CET_S (bit 12) supported (CET supervisor state)
    reserved_2: u4, // Reserved
    xcr0_tileconfig: u1, // XCR0.TILECONFIG (bit 17) supported (AMX can manage TILECONFIG)
    xcr0_tiledata: u1, // XCR0.TILEDATA (bit 18) supported (AMX can manage TILEDATA)
    reserved_3: u13, // Reserved

    xsave_sz_xcr0_enabled: u32, // XSAVE/XRSTOR area byte size, for XCR0 enabled features

    xsave_sz_max: u32, // XSAVE/XRSTOR area max byte size, all CPU features

    u32: u30, // Reserved
    xcr0_lwp: u1, // AMD XCR0.LWP (bit 62) supported (Light-weight Profiling)
    reserved_4: u1, // Reserved
};

/// Leaf 0x80000001
/// Extended CPU feature identifiers
pub const leaf_0x80000001_0 = packed struct(u128) {
    e_stepping_id: u4, // Stepping ID
    e_base_model: u4, // Base processor model
    e_base_family: u4, // Base processor family
    e_base_type: u2, // Base processor type (Transmeta)
    reserved_0: u2, // Reserved
    e_ext_model: u4, // Extended processor model
    e_ext_family: u8, // Extended processor family
    reserved_1: u4, // Reserved

    brand_id: u16, // Brand ID
    reserved_2: u12, // Reserved
    pkg_type: u4, // Package type

    lahf_lm: u1, // LAHF and SAHF in 64-bit mode
    cmp_legacy: u1, // Multi-processing legacy mode (No HT)
    svm: u1, // Secure Virtual Machine
    extapic: u1, // Extended APIC space
    cr8_legacy: u1, // LOCK MOV CR0 means MOV CR8
    lzcnt_abm: u1, // LZCNT advanced bit manipulation
    sse4a: u1, // SSE4A support
    misaligned_sse: u1, // Misaligned SSE mode
    _3dnow_prefetch: u1, // 3DNow PREFETCH/PREFETCHW support
    osvw: u1, // OS visible workaround
    ibs: u1, // Instruction based sampling
    xop: u1, // XOP: extended operation (AVX instructions)
    skinit: u1, // SKINIT/STGI support
    wdt: u1, // Watchdog timer support
    reserved_3: u1, // Reserved
    lwp: u1, // Lightweight profiling
    fma4: u1, // 4-operand FMA instruction
    tce: u1, // Translation cache extension
    reserved_4: u1, // Reserved
    nodeid_msr: u1, // NodeId MSR (0xc001100c)
    reserved_5: u1, // Reserved
    tbm: u1, // Trailing bit manipulations
    topoext: u1, // Topology Extensions (leaf 0x8000001d)
    perfctr_core: u1, // Core performance counter extensions
    perfctr_nb: u1, // NB/DF performance counter extensions
    reserved_6: u1, // Reserved
    data_bp_ext: u1, // Data access breakpoint extension
    perf_tsc: u1, // Performance time-stamp counter
    perfctr_llc: u1, // LLC (L3) performance counter extensions
    mwaitx: u1, // MWAITX/MONITORX support
    addr_mask_ext: u1, // Breakpoint address mask extension (to bit 31)
    reserved_7: u1, // Reserved

    e_fpu: u1, // Floating-Point Unit on-chip (x87)
    e_vme: u1, // Virtual-8086 Mode Extensions
    e_de: u1, // Debugging Extensions
    e_pse: u1, // Page Size Extension
    e_tsc: u1, // Time Stamp Counter
    e_msr: u1, // Model-Specific Registers (RDMSR and WRMSR support)
    pae: u1, // Physical Address Extensions
    mce: u1, // Machine Check Exception
    cx8: u1, // CMPXCHG8B instruction
    apic: u1, // APIC on-chip
    reserved_8: u1, // Reserved
    syscall: u1, // SYSCALL and SYSRET instructions
    mtrr: u1, // Memory Type Range Registers
    pge: u1, // Page Global Extensions
    mca: u1, // Machine Check Architecture
    cmov: u1, // Conditional Move Instruction
    pat: u1, // Page Attribute Table
    pse36: u1, // Page Size Extension (36-bit)
    reserved_9: u1, // Reserved
    obsolete_mp_bit: u1, // Out-of-spec AMD Multiprocessing bit
    nx: u1, // No-execute page protection
    reserved_10: u1, // Reserved
    mmxext: u1, // AMD MMX extensions
    e_mmx: u1, // MMX instructions
    e_fxsr: u1, // FXSAVE and FXRSTOR instructions
    fxsr_opt: u1, // FXSAVE and FXRSTOR optimizations
    page1gb: u1, // 1-GB large page support
    rdtscp: u1, // RDTSCP instruction
    reserved_11: u1, // Reserved
    lm: u1, // Long mode (x86-64, 64-bit support)
    _3dnowext: u1, // AMD 3DNow extensions
    _3dnow: u1, // 3DNow instructions
};

/// Leaf 0x80000007
/// CPU power management (mostly AMD) and AMD RAS enumeration
pub const leaf_0x80000007_0 = packed struct(u128) {
    reserved_0: u32, // Reserved

    mca_overflow_recovery: u1, // MCA overflow conditions not fatal
    succor: u1, // Software containment of uncorrectable errors
    hw_assert: u1, // Hardware assert MSRs
    scalable_mca: u1, // Scalable MCA (MCAX MSRs)
    reserved_1: u28, // Reserved

    cpu_pwr_sample_ratio: u32, // CPU power sample time ratio

    digital_temp: u1, // Digital temperature sensor
    powernow_freq_id: u1, // PowerNOW! frequency scaling
    powernow_volt_id: u1, // PowerNOW! voltage scaling
    thermal_trip: u1, // THERMTRIP (Thermal Trip)
    hw_thermal_control: u1, // Hardware thermal control
    sw_thermal_control: u1, // Software thermal control
    _100mhz_steps: u1, // 100 MHz multiplier control
    hw_pstate: u1, // Hardware P-state control
    constant_tsc: u1, // TSC ticks at constant rate across all P and C states
    core_perf_boost: u1, // Core performance boost
    eff_freq_ro: u1, // Read-only effective frequency interface
    proc_feedback: u1, // Processor feedback interface (deprecated)
    proc_power_reporting: u1, // Processor power reporting interface
    connected_standby: u1, // CPU Connected Standby support
    rapl_interface: u1, // Runtime Average Power Limit interface
    reserved_2: u17, // Reserved
};

/// Leaf 0x80000008
/// CPU capacity parameters and extended feature flags (mostly AMD)
pub const leaf_0x80000008_0 = packed struct(u128) {
    phys_addr_bits: u8, // Max physical address bits
    virt_addr_bits: u8, // Max virtual address bits
    guest_phys_addr_bits: u8, // Max nested-paging guest physical address bits
    reserved_0: u8, // Reserved

    clzero: u1, // CLZERO supported
    insn_retired_perf: u1, // Instruction retired counter MSR
    xsave_err_ptr: u1, // XSAVE/XRSTOR always saves/restores FPU error pointers
    invlpgb: u1, // INVLPGB broadcasts a TLB invalidate to all threads
    rdpru: u1, // RDPRU (Read Processor Register at User level) supported
    reserved_1: u1, // Reserved
    mba: u1, // Memory Bandwidth Allocation (AMD bit)
    reserved_2: u1, // Reserved
    mcommit: u1, // MCOMMIT (Memory commit) supported
    wbnoinvd: u1, // WBNOINVD supported
    reserved_3: u2, // Reserved
    ibpb: u1, // Indirect Branch Prediction Barrier
    wbinvd_int: u1, // Interruptible WBINVD/WBNOINVD
    ibrs: u1, // Indirect Branch Restricted Speculation
    stibp: u1, // Single Thread Indirect Branch Prediction mode
    ibrs_always_on: u1, // IBRS always-on preferred
    stibp_always_on: u1, // STIBP always-on preferred
    ibrs_fast: u1, // IBRS is preferred over software solution
    ibrs_same_mode: u1, // IBRS provides same mode protection
    no_efer_lmsle: u1, // EFER[LMSLE] bit (Long-Mode Segment Limit Enable) unsupported
    tlb_flush_nested: u1, // INVLPGB RAX[5] bit can be set (nested translations)
    reserved_4: u1, // Reserved
    amd_ppin: u1, // Protected Processor Inventory Number
    amd_ssbd: u1, // Speculative Store Bypass Disable
    virt_ssbd: u1, // virtualized SSBD (Speculative Store Bypass Disable)
    amd_ssb_no: u1, // SSBD is not needed (fixed in hardware)
    cppc: u1, // Collaborative Processor Performance Control
    amd_psfd: u1, // Predictive Store Forward Disable
    btc_no: u1, // CPU not affected by Branch Type Confusion
    ibpb_ret: u1, // IBPB clears RSB/RAS too
    branch_sampling: u1, // Branch Sampling supported

    cpu_nthreads: u8, // Number of physical threads - 1
    reserved_5: u4, // Reserved
    apicid_coreid_len: u4, // Number of thread core ID bits (shift) in APIC ID
    perf_tsc_len: u2, // Performance time-stamp counter size
    reserved_6: u14, // Reserved

    invlpgb_max_pages: u16, // INVLPGB maximum page count
    rdpru_max_reg_id: u16, // RDPRU max register ID (ECX input)
};