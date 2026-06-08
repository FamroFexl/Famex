pub const CpuState = extern struct {
    rax : u64,  // Accumulator
    rbx : u64,  // Base
    rcx : u64,  // Counter
    rdx : u64,  // Data
    rsi : u64,  // Source string index
    rdi : u64,  // Destination string index
    rsp : u64,  // Stack pointer
    rbp : u64,  // Base pointer
    r8  : u64,  // General purpose regs
    r9  : u64,
    r10 : u64,
    r11 : u64,
    r12 : u64,
    r13 : u64,
    r14 : u64,
    r15 : u64,

    rflags : u64,   // RFLAGS Control register
    rip : u64,      // Instruction pointer

    fs_base : u64,  // User FS.Base
    gs_base : u64,  // User GS.Base

    /// Save general registers from the CPU
    pub extern fn save(state : *CpuState) callconv(.c) void;

    /// Load general registers into the CPU
    pub extern fn load(state : *CpuState) callconv(.c) void;

    /// Get a state's program counter
    pub fn get_pc(state : *@This()) u64 {
        return state.rip;
    }

    /// Set a state's program counter
    pub fn set_pc(state : *@This(), pc : u64) void {
        state.rip = pc;
    }

    /// Get a state's stack
    pub fn get_stack(state : *@This()) u64 {
        return state.rsp;
    }

    /// Set a state's stack
    pub fn set_stack(state : *@This(), stack : u64) void {
        state.rsp = stack;
    }

    /// Get a state's flags
    pub fn get_flags(state : *@This()) u64 {
        return state.rflags;
    }

    /// Set a state's flags
    pub fn set_flags(state : *@This(), flags : u64) void {
        state.rflags = flags;
    }

    /// Get a register pointer from an argument number
    pub fn get_arg(state : *@This(), arg : u8) *u64 {
        return switch (arg) {
            0 => &state.rdi,
            1 => &state.rsi,
            2 => &state.rdx,
            3 => &state.rcx,
            4 => &state.r8,
            5 => &state.r9,
            else => unreachable,
        };
    }

    /// Get the return register pointer
    pub fn get_ret(state : *@This()) *u64 {
        return &state.rax;
    }

    /// Get a register pointer from an argument number (for syscall register format)
    pub fn get_arg_syscall(state : *@This(), arg : u8) *u64 {
        return switch (arg) {
            2 => &state.r10,
            else => get_arg(state, arg),
        };
    }
};

pub const Cr0 = packed struct(u64) {
    pe : bool,      //Protected Mode Enable
    mp : bool,      //Monitor Coprocessor
    em : bool,      //Emulated x87 FPU
    ts : bool,      //Task Switched (x87 FPU Register State Saving)
    et : bool,      //Extension Type (x87 FPU Instructions Supported)
    ne : bool,      //Numeric Error (x87 FPU Arithmetic Error)
    __pad : u10,    // Reserved
    wp : bool,      //Write Protect (Copy On Write support)
    __pad2 : u1,    // Reserved
    am : bool,      //Alignment Mask (Auto Alignment Checking)
    __pad3 : u10,   // Reserved
    nw : bool,      //Not Write Through
    cd : bool,      //Cache Disable
    pg : bool,      //Paging
};

pub extern fn get_cr0() callconv(.c) Cr0;

pub extern fn set_cr0(cr0 : Cr0) callconv(.c) void;

pub const Cr3 = packed struct(u64) {
    bits : packed union(u12) {
        bits : packed struct {
            __pad : u3,     // Reserved
            pcd : bool,     // Page-level Cache Disable
            pwt : bool,     // Page-level Write-Through
            __pad2 : u7,    // Reserved
        },
        pcid : u12,
    },
    pdb : u49,      // Page-Directory Base
    lam_u57 : bool, // User LAM57 enable
    lam_u48 : bool, // User LAM48 enable
    __pad3 : u1,
};

pub extern fn get_cr3() callconv(.c) Cr3;

pub extern fn set_cr3(cr3 : Cr3) callconv(.c) void;

pub const Cr4 = packed struct(u64) {
    vme : bool,         //Virtual-8086 Mode Extensions
    pvi : bool,         //Protected-Mode Virtual Interrupts
    tsd : bool,         //Time Stamp Disable
    de : bool,          //Debugging Extensions
    pse : bool,         //Page Size Extensions
    pae : bool,         //Physical Address Extension
    mce : bool,         //Machine Check Enable
    pge : bool,         //Page Global Enable
    pce : bool,         //Performance-Monitoring Counter Enable
    osfxcr : bool,      //OS Support for FXSAVE and FXRSTOR Instructions
    osxmmexcpt : bool,  //OS Support for Unmasked SIMD Floating-Point Exceptions
    umip : bool,        //User Mode Instruction Prevention
    la57 : bool,        //57-bit linear addresses
    vmxe : bool,        //Virtual Machine Extensions
    smxe : bool,        //Safer Mode Extensions
    __pad : u1,         // Reserved
    fsgsbase : bool,    //Enables Instructions RDFSBASE, RDGSBASE, WRFSBASE, and WRGSBASE
    pcide : bool,       //Enables Process Context Identifiers
    osxsave : bool,     //XSAVE and Processor Extended States
    kl : bool,          //Key Locker
    smep : bool,        //Supervisor-mode execution prevention
    smap : bool,        //Supervisor-mode access prevention
    pke : bool,         //Protection keys for user-mode pages
    cet : bool,         //Control-flow Enforcement Technology
    pks : bool,         //Protection keys for supervisor-mode pages
    uintr : bool,       //User-Interrupts
    __pad2 : u2,        // Reserved
    lam_sup : bool,     //Supervisor Linear-Address Masking
};

pub extern fn get_cr4() callconv(.c) Cr4;

pub extern fn set_cr4(cr4 : Cr4) callconv(.c) void;

pub const Cr8 = packed struct(u64) {
    tpl : u4,       // Task Priority Level
    __pad : u60,    // Reserved
};

pub extern fn get_cr8() callconv(.c) Cr8;

pub extern fn set_cr8(cr8 : Cr8) callconv(.c) void;

pub const Rflags = packed struct(u64) {
    carry : bool,           // Status Carry
    set1 : u1,              // Reserved (must be 1)
    parity : bool,          //Status Parity
    __pad : u1,             // Reserved
    aux_carry : bool,       //Status Auxiliary Carry
    __pad2 : u1,            // Reserved
    zero : bool,            //Status Zero
    sign : bool,            //Status Sign
    trap : bool,            //System Trap
    irq_enable : bool,      //System Interrupt Enable
    direction : bool,       //Control Direction
    overflow : bool,        //Status Overflow
    iopl : u2,              //System I/O Privilege Level
    nested_task : bool,     //System Nested Task
    __pad3 : u1,            // Reserved
    sys_resume : bool,      //System Resume
    virt_8086 : bool,       //System Virtual-8086 Mode
    access : bool,          //System Alignment Check / Access Control
    virt_irq : bool,        //System Virtual Interrupt
    virt_irq_pend :bool,    //System Virtual Interrupt Pending
    id : bool,              //System ID
};

pub extern fn get_rflags() callconv(.c) Rflags;

pub extern fn set_rflags(rflags : Rflags) callconv(.c) void;

pub const SegDesc = packed struct(u64) {
    seg_limit1 : u16,   //Segment limit
    address1 : u24,
    seg_type : u4,
    desc_type : u1,     //0 is system, 1 is code or data
    priv_level : u2,    //Descriptor Privilege Level
    present : bool,     //Segment Present flag
    limit2 : u4,        //Segment limit
    available : bool,   //Unused flag for other use
    code_seg : bool,    //64-bit code segment (IA-32e)
    size : bool,        //Operation size 0 is 16-bit segment, 1 is 32-bit segment
    granularity : bool,
    address2 : u8,
};

pub const Gdtr = packed struct {
    limit : u16,
    base : u64,
};

/// We just need to init a null segment, 4 code/data segments, and a tss segment for each cpu core
///
/// The ordering is important and is expected by the syscall/sysret instructions. Null descriptor
/// must be first, Kmode data must be after Kmode code and Umode data must be after Umode code. This
/// ordering is required by x86. Other segments and their positions are kernel-defined.
pub const GdtLayout = packed struct {
    null_desc : SegDesc,          // Null descriptor
    kmode_code : SegDesc,         // Kernel Mode Code Segment
    kmode_data : SegDesc,         // Kernel Mode Data Segment
    umode_code : SegDesc,         // User Mode Code Segment
    umode_data : SegDesc,         // User Mode Data Segment
    //union tss_desc tss[];   // Task-State Segments, one for each logical core (irq stacks)
};

pub const KMODE_CODE_OFST = @offsetOf(GdtLayout, "kmode_code");
pub const KMODE_DATA_OFST = @offsetOf(GdtLayout, "kmode_data");
pub const UMODE_CODE_OFST = @offsetOf(GdtLayout, "umode_code");
pub const UMODE_DATA_OFST = @offsetOf(GdtLayout, "umode_data");

// CS and SS segment default descriptors
pub const CS_PL0 = KMODE_CODE_OFST | 0;
pub const SS_PL0 = KMODE_DATA_OFST | 0;
pub const CS_PL3 = UMODE_CODE_OFST | 0;
pub const SS_PL3 = UMODE_DATA_OFST | 0;

pub const Idtr = Gdtr;

pub extern fn get_gdt(gdtr : *Gdtr) callconv(.c) void;

pub extern fn set_gdt(gdtr : *Gdtr) callconv(.c) void;

pub const IrqFrame = packed struct {
    err : u64,      // Error code
    rip : u64,      // Program counter
    cs : u64,       // Code segment
    rflags : u64,   // CPU flags
    rsp : u64,      // Stack pointer
    ss : u64        // Stack segment
};

pub extern fn get_idt(idtr : *Idtr) callconv(.c)void;

pub extern fn set_idt(idtr : *Idtr) callconv(.c) void;

pub extern fn get_tss() callconv(.c) u16;

pub extern fn set_tss(tss : u16) callconv(.c) void;

pub extern fn get_tsc() callconv(.c) u64;

pub extern fn tlb_page_flush(page : *anyopaque) callconv(.c) void;

pub const Msrs = enum(u32) {
    MONITOR_FILTER_SIZE = 6,    // Provides info useful for sleeping CPU cores
    APIC_BASE = 27,
    FEATURE_CONTROL = 58,       // Determines virtualization capabilities (VT-x) (practically read only)
    XAPIC_DISABLE_STATUS = 189, // XAPIC disabled in favor of X2APIC
    MTRRCAP = 254,              // Used to determine memory cache capabilities (read only)
    ARCH_CAPABILITIES = 266,    // Enumeration of Architectural Features (read only)
    MCG_CAP = 377,              // Machine error states (read only)
    MCG_STATUS,                 // Machine error check status (read only)
    MCG_CTL,                    // Machine error check control
    THERM_INTERRUPT = 411,      // Enable or disable different processor temperature interrupts
    THERM_STATUS,               // Processor thermals status (read only)
    MISC_ENABLE = 416,          // Misc features
    ENERGY_PERF_BIA = 432,      // Energy policy
    PAT = 631,                  // Page Attribute Table entries
    TSC_DEADLINE = 1760,        // Local APIC Timer TSC Target for Deadline Mode
    EFER = 0xC0000080,
    SYSCALL_STAR = 0xC0000081,
    SYSCALL_LSTAR = 0xC0000082,
    SYSCALL_FMASK = 0xC0000084,
    FS_BASE = 0xC0000100,
    GS_BASE = 0xC0000101,
    KERNEL_GS_BASE = 0xC0000102,
};

pub extern fn get_msr(msr : Msrs) callconv(.c) u64;

pub extern fn set_msr(msr : Msrs, val : u64) callconv(.c) void;

pub const Efer = packed struct(u64) {
    sce : bool,     //SYSCALL/SYSRET instructions enable
    __pad : u8,     // Reserved
    lme : bool,     //IA-32e mode operation enable
    __pad2 : u1,    // Reserved
    lma : bool,     //IA-32e mode operation active
    nxe : bool,     //Execute Disable Bit enable
};

// Selected via paging bits from high to low: PAT, PCD, PWT
pub const PatTypes = enum(u3) {
    UNCACHEABLE = 0,        // (UC) Used for MMIO, etc
    WRITE_COMBINING = 1,    // (WC) Speculative Reads
    WRITE_THROUGH = 4,      // (WT) Cacheable and Speculative Reads
    WRITE_PROTECTED = 5,    // (WP) Cacheable (reads only) and Speculative Reads
    WRITE_BACK = 6,         // (WB) Cacheable and Writeback Cacheable and Speculative Reads
    UNCACHED = 7,           // (UC-) Can be overridden by MTRRs using WC, otherwise identical to (UC)
};

pub const Pat = [8]u8;

pub const ApicBase = packed struct(u64) {
    __pad : u8,         // Reserved
    bsp : bool,         // Bootstrap Processor (set by bios and read-only)
    __pad2 : u1,        // Reserved
    x2apic : bool,      // x2APIC Mode Enable
    apic_ge : bool,     // APIC Global Enable
    apic_base : u52,  // Base Address of APIC is 4KiB aligned, identical to CR3
};

pub const XapicDisableStatus = packed struct(u64) {
    xapic_off : bool,   // Legacy XAPIC (0) Enabled (1) Disabled
    __pad : u63,
};

pub const Xcr0 = packed struct(u64) {
    x87 : bool,         //Must be 1
    sse : bool,         //XSAVE can manage MXCSR and XMM registers
    avx : bool,         //AVX instructions supported and XSAVE can manage upper YMM registers
    bndreg : bool,      //MPX instructions supported and XSAVE can manage bounds registers BND0-BND3
    bndcsr : bool,      //MPX instructions supported and XSAVE can manage the BNDCFGU and BNDSTATUS registers
    opmask : bool,      //AVX-512 instructions supported and XSAVE can manage K0-K7 opmask registers
    zmm_hi256 : bool,   //AVX-512 instructions supported and XSAVE can manage ZMM0-ZMM15 registers
    hi16_zmm : bool,    //AVX-512 instructions supported and XSAVE can manage ZMM16-ZMM31 registers
    __pad : u1,         // Reserved
    pkru : u1,          //XSAVE can manage PKRU register
    __pad2 : u1,        // Reserved
    tilecfg : bool,     //If and tiledata, AMX instructions supported and XSAVE can manage TILECFG register
    tiledata : bool,    //If and tilecfg, AMX instructions supported and XSAVE can manage TILEDATA register
};

pub const MiscEnable = packed struct(u64) {
    fse : bool,         //Fast-Strings Enable
    __pad : u2,         // Reserved
    atcce : bool,       //Automatic Thermal Control Circuit Enable
    __pad2 : u3,        // Reserved
    pma : bool,         //Performance Monitoring Available
    __pad3 : u1,        // Reserved
    hpd : bool,         //Hardware Prefetcher Disable
    fme : bool,         //FERR# Multiplexing Enable
    btsu : bool,        //Branch Trace Storage Unavailable
    pebsu : bool,       //Processor Event Based Sampling Unavailable
    tm2e : bool,        //TM2 Enable
    __pad4 : u2,        // Reserved
    eisste : bool,      //Enhanced Intel SpeedStep Technology Enable
    fsmme : bool,       //Monitor FSM Enable
    aclpd : bool,       //Adjacent Cache Line Prefetch Disable
    eisstsl : bool,     //Enhanced Intel SpeedStep Technology Select Lock
    __pad5 : u1,        // Reserved
    cpuidmax : bool,    //Limit CPUID Maxval
    xtprmd : bool,      //xTPR Message Disable
    __pad6 : u8,        // Reserved
    xdd : bool,         //XD Bit Disable
    __pad7 : u2,        // Reserved
    dcupd : bool,       //DCU Prefetcher Disable
    idad : bool,        //IDA Disable
    ippd : bool,        //IP Prefetcher Disable
};

pub const ArchCap = packed struct(u64) {
    rdcl_no : bool,
    rsba : bool,
    skip_l1dfl_vmentry : bool,
    ssb_no : bool,
    mds_no : bool,
    if_pschange_mc_no : bool,
    tsx_ctrl : bool,
    taa_no : bool,
    mcu_control : bool,
    misc_package_ctls : bool,
    energy_filtering_ctl : bool,
    doitm : bool,
    sbdr_ssdp_no : bool,
    fbsdp_no : bool,
    psdp_no : bool,
    mcu_enum : bool,
    fb_clear_ctrl : bool,
    rrsba : bool,
    bhi_no : bool,
    xapic_ds : bool,    //IA32_XPIC_DISABLE_STATUS MSR exists
    mcu_ext_service : bool,
    overclocking_stat : bool,
    pbrsb_no : bool,
    gds_ctrl : bool,
    gds_no : bool,
    rfds_no : bool,
    rfds_clear : bool,
    ign_umonitor_sup : bool,
    mon_umon_mitg_sup : bool,
};

