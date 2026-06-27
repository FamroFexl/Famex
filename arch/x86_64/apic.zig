const std = @import("std");

const kernel = @import("kernel");
const log = kernel.util.log;
const mem = kernel.mm.memory;

const regs = @import("registers.zig");
const irq = @import("irq.zig");
const timers = @import("timers.zig");

var apicRegMap : mem.Vaddr = undefined;
var X2_APIC : bool = false;

pub const LapicVerReg = packed struct(u32) {
    version : u8,           // Version numbers of Local APIC (0x0) 82489DX discreet APIC (0x10-0x15) Integrated APIC
    __pad : u8,
    maxLvtEntry : u8,       // Local Vector Table max entries to configure local interrupts
    eoiSupr : bool,         // Can software stop EOI messaging
};

pub const LapicIdReg = packed struct(u32) {
    __pad : u24,
    apicId : u8,
};

// A Local Vector Table register
pub const LvtReg = packed struct(u32) {
    vector              : u8,              // LVT number
    deliveryMode       : DeliveryMode,     // Interrupt type to be sent (not for lvt_err)
    __pad               : u1 = undefined,
    deliveryStatus     : u1,               // (0) No interrupt pending, (1) Interrupt is pending at processor

    // For LVT_LINT0 or LVT_LINT1 only
    intPinPolarity    : u1,                // (0) Active high, (1) Active low
    remoteIrr          : u1,               // Set when an interrupt is being serviced
    triggerMode        : u1,               // (0) Edge-sensitive, (1) Level Sensitive

    mask                : u1,              // (0) Interrupt reception, (1) Inhibits reception
    // Intel defines 2 bits for support of TSC_DEADLINE. AMD only has single bit.
    timerMode          : TimerMode,        // Timer mode (for lvt_timer only)
    __pad2              : u13 = undefined,

    // Type of interrupt to be sent to the processor
    pub const DeliveryMode = enum(u3) {
        FIXED = 0,
        LOWEST_PRIORITY = 1,  // ICR only
        SMI = 2,
        NMI = 4,
        INIT = 5,
        START_UP = 6,         // ICR only
        EXT_INT = 7,          // LVT reg only
    };

    pub const TimerMode = enum(u2) {
        ONE_SHOT = 0, // Used for tickless kernels
        PERIODIC = 1, // Used for ticking kernels
        DEADLINE = 2, // Intel-only tickless kernel
    };
};

// Error Status Register
pub const EsrReg = packed struct(u32) {
    sendChecksum   : bool,    // Send Checksum (not used)
    recvChecksum   : bool,    // Receive Checksum (not used)
    sendAccept     : bool,    // Send Accept (not used)
    recvAccept     : bool,    // Receive Accept (not used)
    redirIpi       : bool,    // Redirectable IPI
    sendIllVec    : bool,     // Send Illegal Vector
    recvIllVec    : bool,     // Receive Illegal Vector
    illVecAddr    : bool,     // Illegal Register Address
};

// Interrupt Command Register (used for IPIs)
pub const IcrReg = packed struct(u64) {
    vector          : u8,
    deliveryMode   : u3,
    destMode       : DestMode,         // Interrupt type to be sent
    deliveryStatus : u1,               // (0) No interrupt pending, (1) Interrupt is pending at processor (not used in x2apic)
    __pad           : u1 = undefined,
    level           : u1,              // (0) De-Assert, (1) Assert
    triggerMode    : TriggerMode,      // (0) Edge-sensitive, (1) Level Sensitive (when using DMODE_INIT)
    __pad2          : u2 = undefined,
    destShorthand  : DestShorthand,    // Optional shorthand used for destination
    __pad3          : u12 = undefined,
    //Only the top 8 bits contain the ID if x2apic is enabled
    destField      : u32,              // Destination Processor by APIC ID (physical) or MDA (logical)

    pub const DestMode = enum(u1) {
        PHYSICAL = 0,
        LOGICAL = 1,
    };

    pub const TriggerMode = enum(u1) {
        EDGE = 0,
        LEVEL = 1,
    };

    pub const DestShorthand = enum(u2) {
        NONE = 0,
        SELF = 1,
        SELF_INCLUSIVE = 2,
        SELF_EXCLUSIVE = 3,
    };
};

// Logical Destination Register
pub const LdrReg = packed struct(u32) {
    __pad       : u24 = undefined,
    logApicId : u8,    // Logical APIC ID
};

// Destination Format Register
pub const DfrReg = packed struct(u32) {
    __pad : u28 = undefined,
    model : DfrModel,

    pub const DfrModel = enum(u4) {
        CLUSTER = 0,
        FLAT = 15,
    };
};

// Generic Priority Register (TPR, APR, PPR)
pub const PrioReg = packed struct(u32) {
    subClass   : u4,
    prioClass  : u4,
};

// Timer Divide Configuration Register
pub const TimerDcReg = packed struct(u32) {
    divVal : DivideValue,
    __pad : u28 = undefined,

    // Timer Divide Configuration values
    pub const DivideValue = enum(u4) {
        BY_2 = 0,
        BY_4 = 1,
        BY_8 = 2,
        BY_16 = 3,
        BY_32 = 8,
        BY_64 = 9,
        BY_128 = 10,
        BY_1 = 11,
    };
};

// Generic Interrupt Pending Register (IRR, ISR, TMR)
pub const IprReg = packed struct(u256) {
    __pad : u16 = undefined,
    vec1 : u48,   // Pending vectors
    vec2 : u64,
    vec3 : u64,
    vec4 : u64,
};

// Spurious Interrupt Vector Register
pub const SvrReg = packed struct(u64) {
    vector      : u8,      // Spurious Vector
    apic_on     : bool,    // APIC Software (0) disable, (1) enable
    fpc         : bool,    // Focused Processor Checking
    __pad       : u2 = undefined,
    eoiSupr    : bool,     // EIO-Broadcast Suppression
    __pad2      : u51 = undefined,
};

const ApicReg = enum {
    lid,        // Local APIC ID Register
    lvr,        // Local APIC Version Register
    tpr,        // (TPR) Task Priority Register
    apr,        // (APR) Arbitration Priority Register (Impl-Dependant)
    ppr,        // (PPR) Processor Priority Register
    eoi,        // (EOI) End Of Interrupt Register
    rrd,        // (RRD) Remote Read Register(Impl-Dependant)
    ldr,        // Logical Destination Register (Read-Only in x2APIC)
    dfr,        // Destination Format Register (xAPIC-only)
    svr,        // Spurious Interrupt Vector Register
    isr,        // (ISR) In-Service Register
    tmr,        // (TMR) Trigger Mode Register
    irr,        // (IRR) Interrupt Request Register
    esr,        // Error Status Register
    lvtCmci,    // (CMCI) LVT Corrected Machine Check Interrupt Register
    icr,        // (ICR) Interrupt Command Register
    lvtTimer,   // LVT Timer Register
    lvtTs,      // LVT Thermal Sensor Register (Impl-Dependant)
    lvtPmc,     // LVT Performance Monitoring Counters Register (Impl-Dependant)
    lvtLint0,   // LVT LINT0 Register
    lvtLint1,   // LVT LINT1 Register
    lvtErr,     // LVT Error Register
    timerIc,    // Initial Count Register (for Timer)
    timerCc,    // Current Count Register (for Timer)
    timerDc,    // Divide Configuration Register (for Timer)
    selfIpi,    // Self IPI Register (x2APIC-Only)
};

const RegInfo = struct {
    offset : u16,               // Offset in 4-byte units
    size : type,

    xread : bool = true,        // Register can be read from in XApic
    xwrite : bool = true,       // Register can be written to in XApic
    x2read : bool = true,       // Register can be read from in X2Apic
    x2write : bool = true,      // Register can be written to in X2Apic
};

fn getRegInfo(comptime reg : ApicReg) RegInfo {
    return switch (reg) {
        .lid        => RegInfo{.offset = 8, .size = LapicIdReg, .xwrite = false},
        .lvr        => RegInfo{.offset = 12, .size = LapicVerReg, .xwrite = false},
        .tpr        => RegInfo{.offset = 32, .size = PrioReg},
        .apr        => RegInfo{.offset = 36, .size = PrioReg, .xwrite = false},
        .ppr        => RegInfo{.offset = 40, .size = PrioReg},
        .eoi        => RegInfo{.offset = 44, .size = u32, .xread = false},
        .rrd        => RegInfo{.offset = 48, .size = u32, .xwrite = false},
        .ldr        => RegInfo{.offset = 52, .size = LdrReg, .x2write = false},
        .dfr        => RegInfo{.offset = 56, .size = DfrReg, .x2read = false, .x2write = false},
        .svr        => RegInfo{.offset = 60, .size = SvrReg},
        .isr        => RegInfo{.offset = 64, .size = IprReg, .xwrite = false},
        .tmr        => RegInfo{.offset = 96, .size = IprReg, .xwrite = false},
        .irr        => RegInfo{.offset = 128, .size = IprReg, .xwrite = false},
        .esr        => RegInfo{.offset = 160, .size = EsrReg},
        .lvtCmci    => RegInfo{.offset = 188, .size = LvtReg},
        .icr        => RegInfo{.offset = 192, .size = IcrReg},
        .lvtTimer   => RegInfo{.offset = 200, .size = LvtReg},
        .lvtTs      => RegInfo{.offset = 204, .size = LvtReg},
        .lvtPmc     => RegInfo{.offset = 208, .size = LvtReg},
        .lvtLint0   => RegInfo{.offset = 212, .size = LvtReg},
        .lvtLint1   => RegInfo{.offset = 216, .size = LvtReg},
        .lvtErr     => RegInfo{.offset = 220, .size = LvtReg},
        .timerIc    => RegInfo{.offset = 224, .size = u32},
        .timerCc    => RegInfo{.offset = 228, .size = u32, .xwrite = false},
        .timerDc    => RegInfo{.offset = 248, .size = TimerDcReg},
        .selfIpi    => RegInfo{.offset = 252, .size = u32, .xread = false, .xwrite = false, .x2read = false},
    };
}

fn getApicOffset(offset : anytype) u64 {
    return apicRegMap.val + offset;
}

fn getApicMsrOffset(offset : anytype) u32 {
    return @intFromEnum(regs.Msr.X2APIC_MSR_BASE) + offset/16;
}

fn assign4To16(in : [*]const u32, out : [*]u32, num : usize) void {
    for (0..num) |i| {
        out[i*4] = in[i];
    }
}

fn assign16To4(in : [*]const u32, out : [*]u32, num : usize) void {
    for (0..num) |i| {
        out[i] = in[i*4];
    }
}

fn getApicMsr(msr : u32, out : [*]u32, num : usize) void {
    const offset = getApicMsrOffset(msr);

    for (0..num) |i| {
        out[i] = regs.getMsr(offset + i);
    }
}

fn setApicMsr(msr : u32, out : [*]const u32, num: usize) void {
    const offset = getApicMsrOffset(msr);

    for (0..num) |i| {
        regs.setMsr(@intCast(offset + i), out[i]);
    }
}

fn apicGetReg(comptime T : type, offset : anytype) T {
    const num = @sizeOf(T)/4;
    const out : [num]u32 = undefined;
    if (X2_APIC) {
        getApicMsr(offset, &out, num);
    }
    else {
        assign16To4(@ptrFromInt(getApicOffset(offset)), &out, num);
    }

    return @bitCast(out);
}

fn apicSetReg(comptime T : type, offset : anytype, val : T) void {
    const num = @sizeOf(T)/4;
    const in : [num]u32 = @bitCast(val);
    if (X2_APIC) {
        setApicMsr(offset, &in, num);
    }
    else {
        // Because ICR is the only 64-bit register, and because setting the lower 32 bits triggers
        // it to send an IPI, we must set the top 32 bits first if it is xAPIC MMIO
        if (num == 2) {
            assign4To16(in[1..2].ptr, @ptrFromInt(getApicOffset(offset + 4)), 1);
            assign4To16(in[0..1].ptr, @ptrFromInt(getApicOffset(offset)), 1);
        }
        else {
            assign4To16(&in, @ptrFromInt(getApicOffset(offset)), num);
        }
    }
}

pub fn get(comptime reg : ApicReg) getRegInfo(reg).size {
    const info = getRegInfo(reg);

    std.debug.assert(if (X2_APIC) info.x2read else info.xread);

    return apicGetReg(info.size, info.offset);
}

pub fn set(comptime reg : ApicReg, val : getRegInfo(reg).size) void {
    const info = getRegInfo(reg);

    std.debug.assert(if (X2_APIC) info.x2write else info.xwrite);

    apicSetReg(info.size, info.offset, val);
}

pub fn setIcrDest(icr : *IcrReg, dest : u32) void {
    if (X2_APIC) {
        icr.destField = dest;
    }
    else {
        icr.destField = dest << 24;
    }
}

pub fn setupTimer() void {
    set(.timerDc, .{
        .divVal = .BY_1,
    });

    var lvtTimer = std.mem.zeroes(LvtReg);
    lvtTimer.vector = @intFromEnum(irq.VecNum.LOCAL_TIMER);
    lvtTimer.mask = 0;
    lvtTimer.deliveryMode = .FIXED;
    lvtTimer.timerMode = if (timers.TSC_DEADLINE and timers.TSC_INVARIANT) .DEADLINE else .ONE_SHOT;
    set(.lvtTimer, lvtTimer);
}

// This needs to be run per-core
pub fn setupCore() void {
    // Disable the TPL/TPR, we don't use it
    regs.Cr8.set(std.mem.zeroes(regs.Cr8));

    // Activate Local xAPIC
    var apicBase = regs.ApicBase.get();
    apicBase.apic_ge = true;
    if (X2_APIC) {
        apicBase.x2apic = true;
        apicBase.apic_base = 0;
    }
    else {
        apicBase.x2apic = false;
        apicBase.apic_base = @intCast(apicRegMap.to_phys().val >> 12);
    }
    regs.ApicBase.set(apicBase);

    setupTimer();

    var svrReg= std.mem.zeroes(SvrReg);
    svrReg.apic_on = true;
    svrReg.vector = @intFromEnum(irq.VecNum.SIVR);
    svrReg.eoiSupr = true;
    set(.svr, svrReg);
}

pub fn setup() void {
    log.print("\narch: Setting up Advanced Programmable Interrupt Controller (APIC)\n", .{});
}