const builtin = @import("builtin");

const is_kernel = builtin.target.os.tag == .freestanding;
const MAX_NUM_CPUS = if (is_kernel) @import("kernel").config.MAX_NUM_CPUS else 0;
const print = if (is_kernel) @import("kernel").util.log.print;
const bin = if (is_kernel) @import("kernel").util.binary;
const cpu = if (is_kernel) @import("arch_api").cpu;

const std = @import("std");

pub const CpuState = extern struct {
    rax : u64,
    rbx : u64,
    rcx : u64,
    rdx : u64,
    rsi : u64,
    rdi : u64,
    rsp : u64,  // Stack pointer
    rbp : u64,
    r8  : u64,
    r9  : u64,
    r10 : u64,
    r11 : u64,
    r12 : u64,
    r13 : u64,
    r14 : u64,
    r15 : u64,

    rflags : Rflags,   // Flags register
    rip : u64,      // Instruction pointer

    fs_base : u64,  // User FS.Base
    gs_base : u64,  // User GS.Base

    extern fn saveState(state : *CpuState) callconv(.c) bool;
    /// Save general registers from the CPU
    /// If it returns true, we are saving state, otherwise
    /// we are restoring from the save.
    pub const save = saveState;

    extern fn loadState(state : *CpuState) callconv(.c) noreturn;
    /// Load general registers into the CPU
    pub const load = loadState;

    /// Get a state's program counter
    pub fn getPc(state : *@This()) u64 {
        return state.rip;
    }

    /// Set a state's program counter
    pub fn setPc(state : *@This(), pc : u64) void {
        state.rip = pc;
    }

    /// Get a state's stack
    pub fn getStack(state : *@This()) u64 {
        return state.rsp;
    }

    /// Set a state's stack
    pub fn setStack(state : *@This(), stack : u64) void {
        state.rsp = stack;
    }

    /// Get a state's flags
    pub fn getFlags(state : *@This()) u64 {
        return @bitCast(state.rflags);
    }

    /// Set a state's flags
    pub fn setFlags(state : *@This(), flags : u64) void {
        state.rflags = flags;
    }

    /// Get a register pointer from an argument number
    pub fn getArg(state : *@This(), arg : anytype) *u64 {
        return switch (arg) {
            0 => &state.rdi,
            1 => &state.rsi,
            2 => &state.rdx,
            3 => &state.rcx,
            4 => &state.r8,
            5 => &state.r9,
            else => @panic("CpuState argument number doesn't exist!"),
        };
    }

    /// Get the return register pointer
    pub fn getRet(state : *@This()) *u64 {
        return &state.rax;
    }

    /// Get a register pointer from an argument number (for syscall register format)
    pub fn getArgSys(state : *@This(), arg : anytype) *u64 {
        return switch (arg) {
            3 => &state.r10,
            else => getArg(state, arg),
        };
    }

    pub fn getRetSys(state : *@This()) *u64 {
        return getRet(state);
    }

    pub inline fn inKmode(this : *@This()) bool {
        if (is_kernel)
            return @import("kernel").pm.process.inKmode(this);

        return false;
    }

    pub fn init(state : *@This()) void {
        if (is_kernel) state.* = @import("arch").cpu.CPU_STATE_INIT;
    }

    /// Used for sanitizing ucontext flags
    pub fn sanitizeRetFlags(state : *@This()) void {
        state.rflags.set1 = 1;
        state.rflags.irq_enable = true;
        state.rflags.iopl = 0;
        state.rflags.nested_task = false;
        state.rflags.sys_resume = false;
        state.rflags.virt_8086 = false;
        state.rflags.virt_irq = false;
        state.rflags.virt_irq_pend = false;
        state.rflags.access = false;
        state.rflags.trap = false;

        state.rflags.__pad = 0;
        state.rflags.__pad2 = 0;
        state.rflags.__pad3 = 0;
        state.rflags.__pad4 = 0;
    }
};

pub extern fn fpStateReset() callconv(.c) void;

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
    __pad4 : u32,

    extern fn getCr0() callconv(.c) Cr0;
    pub const get = getCr0;

    extern fn setCr0(cr0 : Cr0) callconv(.c) void;
    pub const set = setCr0;
};

pub const Cr2 = struct {
    extern fn getCr2() callconv(.c) u64;
    pub const get = getCr2;
};

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


    extern fn getCr3() callconv(.c) Cr3;
    pub const get = getCr3;

    extern fn setCr3(cr3 : Cr3) callconv(.c) void;
    pub const set = setCr3;
};

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
    __pad3 : u35,

    extern fn getCr4() callconv(.c) Cr4;
    pub const get = getCr4;

    extern fn setCr4(cr4 : Cr4) callconv(.c) void;
    pub const set = setCr4;
};

pub const Cr8 = packed struct(u64) {
    tpl : u4,       // Task Priority Level
    __pad : u60,    // Reserved

    extern fn getCr8() callconv(.c) Cr8;
    pub const get = getCr8;

    extern fn setCr8(cr8 : Cr8) callconv(.c) void;
    pub const set = setCr8;
};

extern fn getXCr(xcr : u32) callconv(.c) u64;
extern fn setXCr(xcr : u32, val : u64) callconv(.c) void;

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
    pkru : bool,          //XSAVE can manage PKRU register
    __pad2 : u1,        // Reserved
    tilecfg : bool,     //If and tiledata, AMX instructions supported and XSAVE can manage TILECFG register
    tiledata : bool,    //If and tilecfg, AMX instructions supported and XSAVE can manage TILEDATA register
    __pad3 : u51,

    pub fn get() Xcr0 {
        return @bitCast(getXCr(0));
    }

    pub fn set(val : Xcr0) void {
        setXCr(0, @bitCast(val));
    }
};

// Vol 1, Chapter 8.1.3, Intel SDM
pub const X87Status = packed struct(u16) {
    // Exception flags
    invalidOperation        : bool,
    denormalizedOperand     : bool,
    zeroDivide              : bool,
    overflow                : bool,
    underflow               : bool,
    precision               : bool,

    stackFault              : bool,
    xcpSumStat              : bool,  // Exception summary status
    code1                   : u3,
    tosPtr                  : u3,    // Top of stack pointer
    code2                   : u1,
    fpuBusy                 : bool,

    extern fn getX87Status() callconv(.c) @This();
    pub const get = getX87Status;

    extern fn clearX87Status() callconv(.c) void;
    pub const clear = clearX87Status;
};

// Vol 1, Chapter 10.2.3, Intel SDM
pub const MxcsrStatus = packed struct(u32) {
    // Exception flags
    invalidOperation        : bool,
    denormalizedOperand     : bool,
    zeroDivide              : bool,
    overflow                : bool,
    underflow               : bool,
    precision               : bool,

    denormalsAreZero        : bool,
    invalidOperationMask    : bool,
    denormalizedOperandMask : bool,
    zeroDivideMask          : bool,
    overflowMask            : bool,
    underflowMask           : bool,
    precisionMask           : bool,

    roundingCtrl            : u2,
    flushToZero             : bool,
    __pad1                  : u16,

    extern fn getMxcsrStatus() callconv(.c) @This();
    pub const get = getMxcsrStatus;

    extern fn clearMxcsrStatus() callconv(.c) void;
    pub const clear = clearMxcsrStatus;
};

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
    __pad4 : u42,

    extern fn getRflags() callconv(.c) Rflags;
    pub const get = getRflags;

    extern fn setRflags(rflags : Rflags) callconv(.c) void;
    pub const set = setRflags;
};

// System segment types
pub const SysSegType = enum(u4) {
    LDT = 2,                // Not used
    TSS_AVAILABLE = 9,
    TSS_BUSY = 11,          // Not used
    CALL_GATE = 12,         // Not used
    INTERRUPT_GATE = 14,    // For un-nestable interrupts
    TRAP_GATE = 15          // Not used
};

pub const SegDesc = packed struct(u64) {
    limit1          : u16 = std.math.maxInt(u16),
    address1        : u24 = 0,
    seg_type        : CDSegType,
    desc_type       : u1 = 1,       //0 is system, 1 is code or data
    priv_level      : u2,           //Descriptor Privilege Level
    present         : bool = true,  //Segment Present flag
    limit2          : u4 = std.math.maxInt(u4),
    __pad1          : u1 = 0,       //Unused flag for other use
    code_seg        : bool,         //64-bit code segment (IA-32e)
    size            : bool,         //Operation size 0 is 16-bit segment, 1 is 32-bit segment
    granularity     : bool = true,
    address2        : u8 = 0,

    // Code or Data segment types
    pub const CDSegType = enum(u4) {
        SEG_DATA_RO = 0,        // Read-Only
        SEG_DATA_ROA = 1,       // Read-Only, accessed
        SEG_DATA_RW = 2,        // Read/Write
        SEG_DATA_RWA = 3,       // Read/Write, accessed
        SEG_DATA_ROED = 4,      // Read-Only, expand-down
        SEG_DATA_ROEDA = 5,     // Read-Only, expand-down, accessed
        SEG_DATA_RWED = 6,      // Read/Write, expand-down
        SEG_DATA_RWEDA = 7,     // Read/Write, expand-down, accessed

        SEG_CODE_EO = 8,        // Execute-Only
        SEG_CODE_EOA = 9,       // Execute-Only, accessed
        SEG_CODE_ER = 10,       // Execute/Read
        SEG_CODE_ERA = 11,      // Execute/Read, accessed
        SEG_CODE_EOC = 12,      // Execute-Only, conforming
        SEG_CODE_EOCA = 13,     // Execute-Only, conforming, accessed
        SEG_CODE_ERC = 14,      // Execute/Read, conforming
        SEG_CODE_ERCA = 15      // Execute/Read, conforming, accessed
    };
};

pub const TssDesc = packed struct {
    seg_limit1      : u16 = @sizeOf(Tss) - 1,
    address1        : u24,
    seg_type        : SysSegType = .TSS_AVAILABLE,
    __zero1         : u1 = 0,
    desc_priv_lvl   : u2 = 0,   // Descriptor Privilege Level
    seg_present     : bool = true,     // Segment present flag
    seg_limit2      : u4 = 0,
    __pad1          : bool = false,     // Unused flag for other use
    __zero2         : u2 = 0,
    granularity     : bool = false,
    address2        : u48,
    __rsvd1         : u8 = 0,
    __zero3         : u5 = 0,
    __rsvd2         : u19 = 0,
};

pub const Gdtr = packed struct(u80) {
    limit : u16 = @sizeOf(Layout) - 1,
    base : u64,

    comptime {std.debug.assert(@offsetOf(Gdtr, "limit") + 2 == @offsetOf(Gdtr, "base"));}

    /// We just need to init a null segment, 4 code/data segments, and a tss segment for each cpu core
    ///
    /// The ordering is important and is expected by the syscall/sysret instructions. Null descriptor
    /// must be first, Kmode data must be after Kmode code and Umode data must be after Umode code. This
    /// ordering is required by x86. Other segments and their positions are kernel-defined.
    pub const Layout = struct {
        null_desc  : SegDesc = std.mem.zeroes(SegDesc),  // Null descriptor
        kmode_code : SegDesc,      // Kernel Mode Code Segment
        kmode_data : SegDesc,      // Kernel Mode Data Segment
        umode_data : SegDesc,      // User Mode Code Segment
        umode_code : SegDesc,      // User Mode Data Segment

        // Task-State Segments, one for each logical core (irq stacks)
        pub fn getTss(this : *@This()) []TssDesc {
            return bin.getFlexArray(Layout, TssDesc, this)[0..cpu.FEATURES.NUM_CPU_CORES];
        }

        comptime { std.debug.assert(@sizeOf(Layout) == 40); }
    };

    extern fn getGdtr(gdtr : *Gdtr) callconv(.c) void;
    pub const get = getGdtr;

    extern fn setGdtr(gdtr : *Gdtr) callconv(.c) void;
    pub const set = setGdtr;
};

pub const Idtr = packed struct(u80) {
    limit : u16 = @sizeOf(Layout) - 1,
    base : u64,

    pub const Layout = struct {
        id_gate : [256]IdtGateDesc,

        comptime { std.debug.assert(@alignOf(@This()) == 8); }
    };

    pub const IdtGateDesc = struct {
        word1 : packed struct(u64) {
            offset1         : u16,
            seg_select      : u16 = @offsetOf(Gdtr.Layout, "kmode_code"),
            ist             : u3,       // Interrupt Stack Table (used only if seg_type is INTERRUPT_GATE or TRAP_GATE)
            __zero1         : u5 = 0,
            gate_type       : SysSegType = .INTERRUPT_GATE,
            __zero2         : u1 = 0,
            priv_lvl        : u2 = 0,
            present         : bool = true,
            offset2         : u16,
        },
        word2 : packed struct(u64) {
            offset3         : u32,
            __rsvd1         : u32 = 0,
        },
    };

    extern fn getIdtr(idtr : *Idtr) callconv(.c)void;
    pub const get = getIdtr;

    extern fn setIdtr(idtr : *Idtr) callconv(.c) void;
    pub const set = setIdtr;
};

pub const Tss = packed struct(u832) {
    __rsvd1     : u32 = 0,
    rsp0        : u64,      // Stack pointers for privilege levels 0-2
    rsp1        : u64,
    rsp2        : u64,
    __rsvd2     : u64 = 0,
    ist1        : u64,      // Interrupt Stack Table (IST) pointers (ist[0] is ist1)
    ist2        : u64,
    ist3        : u64,
    ist4        : u64,
    ist5        : u64,
    ist6        : u64,
    ist7        : u64,
    __rsvd3     : u64 = 0,
    __rsvd4     : u16 = 0,
    iom_base    : u16 = std.math.maxInt(u16),   // 16-bit offset to the I/O permission bit map from the TSS base (disabled)

    comptime { std.debug.assert(@offsetOf(Tss, "rsp0") == 4);}
    //comptime { //std.debug.assert(@sizeOf(@This()) == 104); }

    extern fn getTss() callconv(.c) u16;
    pub const get = getTss;

    extern fn setTss(tss : u16) callconv(.c) void;
    pub const set = setTss;
};

pub const IrqFrame = struct {
    err : u64,      // Error code
    rip : u64,      // Program counter
    cs : u64,       // Code segment
    rflags : u64,   // CPU flags
    rsp : u64,      // Stack pointer
    ss : u64,       // Stack segment
};

pub extern fn getTsc() callconv(.c) u64;

pub extern fn tlbPageFlush(page : *anyopaque) callconv(.c) void;

pub extern fn getMsr(msr : u32) callconv(.c) u64;
pub extern fn setMsr(msr : u32, val : u64) callconv(.c) void;

pub fn CreateMsr(comptime msr : u32, comptime T : type) type {
    comptime {
        if (@bitSizeOf(T) != 64)
            @compileError("Msr must be 64 bits!");
    }

    return struct {
        pub const Layout = T;
        pub const addr = msr;

        pub fn get() Layout {
            return @bitCast(getMsr(addr));
        }

        pub fn set(reg : Layout) void {
            setMsr(addr, @bitCast(reg));
        }
    };
}

pub fn CreateReadMsr(comptime msr : u32, comptime T : type) type {
    comptime {
        if (@bitSizeOf(T) != 64)
            @compileError("Msr must be 64 bits!");
    }

    return struct {
        pub const Layout = T;
        pub const addr = msr;

        pub fn get() Layout {
            return @bitCast(getMsr(addr));
        }
    };
}

pub const Msr = enum(u32) {
    MONITOR_FILTER_SIZE = 6,    // Provides info useful for sleeping CPU cores
    FEATURE_CONTROL = 58,       // Determines virtualization capabilities (VT-x) (practically read only)
    XAPIC_DISABLE_STATUS = 189, // XAPIC disabled in favor of X2APIC
    MTRRCAP = 254,              // Used to determine memory cache capabilities (read only)
    MCG_CAP = 377,              // Machine error states (read only)
    MCG_STATUS,                 // Machine error check status (read only)
    MCG_CTL,                    // Machine error check control
    THERM_INTERRUPT = 411,      // Enable or disable different processor temperature interrupts
    THERM_STATUS,               // Processor thermals status (read only)
    ENERGY_PERF_BIA = 432,      // Energy policy
    X2APIC_MSR_BASE = 2048,
};

pub const ApicBase = CreateMsr(27, packed struct(u64) {
    __pad : u8 = 0,         // Reserved
    bsp : bool,             // Bootstrap Processor (set by bios and read-only)
    __pad2 : u1 = 0,        // Reserved
    x2apic : bool,          // x2APIC Mode Enable
    apic_ge : bool,         // APIC Global Enable
    apic_base : u52,        // Base Address of APIC is 4KiB aligned, identical to CR3
});

/// XAPIC disabled in favor of X2APIC
pub const XapicDisableStatus = CreateMsr(189, packed struct(u64) {
    xapic_off : bool,   // Legacy XAPIC (0) Enabled (1) Disabled
    __pad : u63 = 0,
});

/// Enumeration of Architectural Features (read only)
pub const ArchCap = CreateReadMsr(266, packed struct(u64) {
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
});

/// Page Attribute Table entries
pub const Pat = CreateMsr(631, packed struct(u64) {
    pa0 : PatType,
    pa1 : PatType,
    pa2 : PatType,
    pa3 : PatType,
    pa4 : PatType,
    pa5 : PatType,
    pa6 : PatType,
    pa7 : PatType,

    // Selected via paging bits from high to low: PAT, PCD, PWT
    pub const PatType = enum(u8) {
        UNCACHEABLE = 0,        // (UC) Used for MMIO, etc
        WRITE_COMBINING = 1,    // (WC) Speculative Reads
        WRITE_THROUGH = 4,      // (WT) Cacheable and Speculative Reads
        WRITE_PROTECTED = 5,    // (WP) Cacheable (reads only) and Speculative Reads
        WRITE_BACK = 6,         // (WB) Cacheable and Writeback Cacheable and Speculative Reads
        UNCACHED = 7,           // (UC-) Can be overridden by MTRRs using WC, otherwise identical to (UC)
    };
});

/// Misc features
pub const MiscEnable = CreateMsr(416, packed struct(u64) {
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
});

/// Local APIC Timer TSC Target for Deadline Mode
pub const TscDeadline = CreateMsr(1760, u64);

pub const Efer = CreateMsr(0xC0000080, packed struct(u64) {
    sce : bool,         //SYSCALL/SYSRET instructions enable
    __pad : u8 = 0,     // Reserved
    lme : bool,         //IA-32e mode operation enable
    __pad2 : u1 = 0,    // Reserved
    lma : bool,         //IA-32e mode operation active
    nxe : bool,         //Execute Disable Bit enable
    __pad3 : u51 = 0,
});

pub const SyscallStar = CreateMsr(0xC0000081, u64);
pub const SyscallLStar = CreateMsr(0xC0000082, u64);
pub const SyscallFMask = CreateMsr(0xC0000084, u64);
pub const FsBase = CreateMsr(0xC0000100, u64);
pub const GsBase = CreateMsr(0xC0000101, u64);
pub const KernelGsBase = CreateMsr(0xC0000102, u64);


