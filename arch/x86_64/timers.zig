const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const time = kernel.pm.time;

const acpica = @import("lib").acpica;
const posix = @import("lib").posix;

const reg = @import("registers.zig");
const cpu = @import("cpu.zig");
const apic = @import("apic.zig");
const ports = @import("ports.zig");

var rtcMap : *Cmos = undefined;
var rtcCenturyReg : ?u8 = null;
var hpetMap : *Hpet = undefined;

const Cmos = packed struct {
    const PORT_OUT = 0x70;
    const PORT_IN = 0x71;

    seconds : u8,       // 0-59
    secAlarm : u8,
    minutes : u8,       // 0-59
    minAlarm : u8,
    hours : u8,         // 1-12 or 0-23
    hourAlarm : u8,
    dayOfWeek : u8,     // 1-7
    dayOfMonth : u8,    // 1-31
    month : u8,         // 1-12
    year : u8,          // 0-99
    regA : RegA,
    regB : RegB,
    regC : RegC,
    regD : RegD,
    rom : u912,    // Extended CMOS storage

    const RegA = packed struct(u8) {
        rs0 : u1,
        rs1 : u1,
        rs2 : u1,
        rs3 : u1,
        dv0 : u1,
        dv1 : u1,
        dv2 : u1,
        uip : bool,
    };

    const RegB = packed struct(u8) {
        dse : bool, // Daylight savings enable
        fmt : u1,   // (0) 12-hour mode or (1) 24-hour mode
        dm  : u1,   // Data mode (0) BCD-coded, (1) Binary-coded
        swe : bool, // Square-Wave Enable
        uie : bool, // Update-ended Interrupt Enable
        aie : bool, // Alarm Interrupt Enable
        pie : bool, // Periodic Interrupt Enable
        set : bool, // Abort update progress
    };

    const RegC = packed struct(u8) {
        __pad0 : u4 = 0,
        uf  : bool,  // Update-ended Interrupt Flag
        af  : bool,  // Alarm Interrupt Flag
        pf  : bool,  // Periodic Interrupt Flag (Read-Only)
        irq : bool, // Is (1) if any above are 1
    };

    const RegD = packed struct(u8) {
        __pad0 : u7 = 0,
        vrt : bool,  // Valid RAM and time
    };
};

const Gcidr = packed struct(u64) {
    revId           : u8,    // Revision ID
    numTimer        : u5,    // Number of timers in the block (starting from 0)
    counterSize     : u1,    // Size of the main counter (0) 32 bits, (1) 64 bits
    __pad1          : u1 = 0,
    legReplRoute    : bool,  // Is Legacy Replacement Route Capable
    vendorId        : u16,
    clockPeriod     : u32,   // How much the counter increments in femtoseconds (more than 0, less than 100ns)
};

const Gcr = packed struct(u64) {
    irqEnable  : bool,     // Main count and timer interrupts (0) disabled, (1) enabled
    // If false, fsb_irr will determine route. Otherwise, timer 0 will be IRQ2 in I/O APIC
    // and timer 1 will be IRQ8 in I/O APIC.
    legReplRoute : bool,   // Legacy Replacement Route (0) Not supported, (1) Supported
    __pad1 : u62 = 0,
};

const Gisr = packed struct(u64) {
    // If level-triggered (not edge-triggered), this indicates if the interrupt for the selected timer is active.
    irqStatus : u64, // Timer interrupt status (1 bit per timer)
};

const Ccr = packed struct(u64) {
    __pad1          : u1 = 0,
    irqType         : u1,      // Interrupt type (0) edge-triggered, (1) level-triggered
    irqEnable       : bool,    // Timer interrupts enable
    irqPeriod       : bool,    // Use Periodic Interrupts (if supported)
    irqPeriodSup    : bool,    // Periodic Interrupts mode supported (Read-Only)
    counterSize     : u1,      // Size of the timer (0) 32 bits, (1) 64 bits (Read-Only)
    softwareSet     : bool,    // Allow software to directly set a periodic timer's accumulator
    __pad2          : u1 = 0,
    force32         : bool,    // Force 64-bit timer to behave as 32-bit timer
    irqRouting      : u5,      // I/O APIC Interrupt Routing
    forceFsb        : bool,    // Force FSB Delivery if Supported
    forceFsbSup     : bool,    // FSB Interrupt Delivery Supported (Read-Only)
    __pad3          : u16 = 0,
    irqRouteCap     : u32,     // Interrupt Routing Capability (Read-Only)
};

const Fsb = packed struct(u64) {
    fsbLoc : u32,   // The location the FSB interrupts should be written to
    fsbMsg : u32,   // Software-set to FSB interrupt message
};

const Hpet = struct {
    gcidr       : Gcidr,        // General Capabilities and ID Register (Read-Only)
    __rsvd1     : u64,
    gcr         : Gcr,          // General Configuration Register (Read/Write)
    __rsvd2     : u64,
    gisr        : Gisr,         // General Interrupt Status Register (timer masks) (Read/Write)
    __rsvd3     : [25]u64,
    mcvr        : u64,          // Main Counter Value Register (Read/Write)
    __rsvd4     : u64,
    timer       : [32]Timer,    // Max number of timers determined by (gcidr.NUM_TIM_CAP + 1)

    const Timer = struct {
        ccr : Ccr,
        cvr : u64,
        fsb : Fsb,
        __rsvd1 : u64,
    };
};

fn getHpet(clock : *kernel.pm.time.Clock) u64 {
    _ = clock;
    return hpetMap.mcvr;
}

/// Setup High Precision Event Timer
fn setupHpet() void {
    var hpet : *acpica.ACPI_TABLE_HPET = undefined;

    if (acpica.ACPI_FAILURE(acpica.AcpiGetTable(@constCast(@ptrCast(acpica.ACPI_SIG_HPET)), 0, @ptrCast(&hpet))) > 0) {
        @panic("Failed to get ACPI HPET Table!");
    }

    kernel.print("  HPET Register Map found at 0x{X}\n", .{hpet.Address.Address});
    hpetMap = cast.toPtr(*Hpet, kernel.mm.paging.mmioMap(.asPhys(hpet.Address.Address), @sizeOf(Hpet), .UNCACHED).ptr());

    // Accesses must be in 64-bit chunks. Values cannot be set directly
    hpetMap.gcr = .{
        .irqEnable = true,
        .legReplRoute = false,
    };

    const clock = kernel.pmalloc(time.Clock);
    time.Clock.CLOCKS.insertFront(&clock.link);

    clock.getRaw = getHpet;
    @memcpy(clock.name[0..4], "HPET");

    // Femptoseconds to tps
    clock.tps = cast.u64(1_000_000_000_000_000) / cast.u64(hpetMap.gcidr.clockPeriod);
}

fn getTsc(clock : *time.Clock) u64 {
    _ = clock;
    return reg.getTsc();
}

fn getTscDeadline(timer : *time.Timer) u64 {
    _ = timer;
    const deadline = reg.TscDeadline.get();
    if (deadline == 0) return 0;

    const tsc = reg.getTsc();

    return deadline - tsc;
}

fn setTscDeadline(timer : *time.Timer, deadline : u64) void {
    _ = timer;
    reg.TscDeadline.set(reg.getTsc() + deadline);
}

/// Setup Time Stamp Counter
fn setupTsc() void {
    if (cpu.leaf_0x87.constant_tsc == 0) {
        kernel.print("  Invariant TSC isn't available! TSC timer cannot be used!\n", .{});
        return;
    }

    const clock = kernel.pmalloc(time.Clock);
    time.Clock.CLOCKS.insertFront(&clock.link);
    @memcpy(clock.name[0..3], "TSC");

    const leaf15 = cpu.cpuid(cpu.cpuid_db.leaf_0x15_0, 0x15, 0);
    if (leaf15.cpu_crystal_hz > 0 and leaf15.tsc_denominator > 0 and leaf15.tsc_numerator > 0) {
        clock.tps = leaf15.cpu_crystal_hz * (leaf15.tsc_numerator / leaf15.tsc_denominator);
    }
    else {
        clock.calibrate(.Msec(50));
    }

    if (cpu.leaf_0x1.tsc_deadline_timer == 1) {
        const timer = kernel.pmalloc(time.Timer);
        time.Timer.TIMERS.insertFront(&timer.link);

        timer.getRaw = getTscDeadline;
        timer.setRaw = setTscDeadline;
        timer.local = true;

        timer.max = std.math.maxInt(u64);
        @memcpy(timer.name[0..3], "TSC");
        timer.tps = clock.tps;
    }
}

fn getLapic(timer : *time.Timer) u64 {
    _ = timer;
    return apic.get(.timerCc);
}

fn setLapic(timer : *time.Timer, count : u64) void {
    _ = timer;
    apic.set(.timerCc, @intCast(count));
}

fn setupLat() void {
    const timer = kernel.pmalloc(time.Timer);
    time.Timer.TIMERS.insertFront(&timer.link);

    timer.getRaw = getLapic;
    timer.setRaw = setLapic;
    timer.local = true;
    timer.max = std.math.maxInt(u32);
    @memcpy(timer.name[0..3], "LAT");

    const leaf6 = cpu.cpuid(cpu.cpuid_db.leaf_0x6_0, 6, 0);

    if (leaf6.lapic_timer_always_on == 0) {
        kernel.print("  LAPIC Timer stops during sleep states or Enhanced Intel SpeedStep transitions!\n", .{});
    }

    const leaf15 = cpu.cpuid(cpu.cpuid_db.leaf_0x15_0, 0x15, 0);

    if (leaf15.cpu_crystal_hz > 0) {
        timer.tps = leaf15.cpu_crystal_hz;
    }
    else {
        timer.calibrate(.Msec(50));
    }
}

fn getCmos() Cmos {
    var cmos : Cmos = undefined;

    for (@offsetOf(Cmos, "rom")..@sizeOf(Cmos)) |i| {
        const cmosU8 : [*]u8 = @ptrCast(&cmos);
        ports.out(Cmos.PORT_OUT, cast.u8(i));
        cmosU8[i] = ports.in(Cmos.PORT_IN, 1);
    }

    return cmos;
}

fn setCmos(cmos : *Cmos) void {
    const cmosU8 = cast.toPtr([*]u8, cmos);

    // Copy in new values
    for (@offsetOf(Cmos, "rom")..@sizeOf(Cmos)) |i| {
        ports.out(Cmos.PORT_OUT, cast.u8(i));
        ports.out(Cmos.PORT_IN, cmosU8[i]);
    }
}

/// Fast RTC read through try-expect
inline fn tryCopy(cmos : [*]u8) bool {
    ports.out(Cmos.PORT_OUT, cast.u8(@offsetOf(Cmos, "regA")));
    const regA : Cmos.RegA = @bitCast(ports.in(Cmos.PORT_IN, u8));
    if (regA.uip) return false;

    for (0..@offsetOf(Cmos, "regA")) |i| {
        ports.out(Cmos.PORT_OUT, cast.u8(i));
        cmos[i] = ports.in(Cmos.PORT_IN, u8);
    }

    return true;
}

/// Copy the RTC CMOS region
fn copyRtc() Cmos {
    var cmos : Cmos = undefined;
    var cmos2 : Cmos = undefined;

    const cmosU8 : [*]u8 = @ptrCast(&cmos);
    const cmos2U8 : [*]u8 = @ptrCast(&cmos2);

    while (true) {
        if (!tryCopy(cmosU8)) continue;

        if (!tryCopy(cmos2U8)) continue;

        if (std.mem.eql(u8, cmosU8[0..@offsetOf(Cmos, "regA")], cmos2U8[0..@offsetOf(Cmos, "regA")]))
            break;
    }

    // Copy remaining registers
    for (@offsetOf(Cmos, "regA")..@offsetOf(Cmos, "regD")) |i| {
        ports.out(Cmos.PORT_OUT, cast.u8(i));
        cmosU8[i] = ports.in(Cmos.PORT_IN, u8);
    }

    return cmos;
}

/// Paste the RTC CMOS region
fn pasteRtc(rtc : *Cmos) void {
    ports.out(Cmos.PORT_OUT, cast.u8(@offsetOf(Cmos, "regB")));
    var regB : Cmos.RegB = @bitCast(ports.in(Cmos.PORT_IN, u8));

    // Stop the clock so it can be replaced
    regB.set = true;

    ports.out(Cmos.PORT_OUT, cast.u8(@offsetOf(Cmos, "regB")));
    ports.out(Cmos.PORT_IN, cast.bit(u8, regB));

    const rtcU8 = cast.toPtr([*]u8, &rtc);

    // Copy in new values
    for (0..@offsetOf(Cmos, "rom")) |i| {
        ports.out(Cmos.PORT_OUT, cast.u8(i));
        ports.out(Cmos.PORT_IN, rtcU8[i]);
    }

    if (rtcCenturyReg) |centuryReg| {
        ports.out(Cmos.PORT_OUT, centuryReg);
        ports.out(Cmos.PORT_IN, rtcU8[centuryReg]);
    }

    // Start the clock with the new values
    regB = rtc.regB;
    regB.set = false;

    ports.out(Cmos.PORT_OUT, cast.u8(@offsetOf(Cmos, "regB")));
    ports.out(Cmos.PORT_IN, cast.bit(u8, regB));
}

/// Get RTC as timespec
fn getRtc() posix.times.tm {
    const rtc : Cmos = copyRtc();

    if (!rtc.regD.vrt) {
        return time.defaultTimespec();
    }

    const cmosU8 : [*]u8 = cast.toPtr([*]u8, &rtc);

    // Convert BCD format to binary if needed
    if (rtc.regB.dm == 0) {
        for (0..@offsetOf(Cmos, "regA")) |i| {
            const cur = cmosU8[i];
            cmosU8[i] = ((cur & 0xF0) >> 1) + ((cur & 0xF0) >> 3) + (cur & 0xF);
        }
    }

    const century : u8 = 20;
    // if (rtcCenturyReg) |centuryReg| {
    //     const cur = cmosU8[centuryReg];
    //     if (rtc.regB.dm == 0) {
    //         // Invalid century register
    //         if ((cur & 0x0F) <= 9 and (cur >> 4) <= 9)
    //             century = ((cur & 0xF0) >> 1) + ((cur & 0xF0) >> 3) + (cur & 0xF);
    //     }
    //     else {
    //         century = cur;
    //     }
    // }

    const curYear : u16 = rtc.year + cast.u16(century)*100;

    return .{
        .tm_sec = rtc.seconds,
        .tm_min = rtc.minutes,
        .tm_hour = rtc.hours,
        .tm_wday = rtc.dayOfWeek,
        .tm_mday = rtc.dayOfMonth,
        .tm_yday = time.dayOfYear(rtc.dayOfMonth, rtc.month - 1, curYear),
        .tm_mon = rtc.month - 1,
        .tm_year = curYear - 1900,
        .tm_isdst = if (rtc.regB.dse) 1 else 0,
    };
}

/// Set RTC as timespec
fn setRtc(tm : posix.times.tm) void {
    var rtc : Cmos = rtcMap.*;

    if (tm.tm_isdst == 1)
        rtc.regB.dse = true;
    rtc.seconds = @intCast(tm.tm_sec);
    rtc.minutes = @intCast(tm.tm_min);
    rtc.hours = @intCast(tm.tm_hour);
    rtc.dayOfWeek = @intCast(tm.tm_wday + 1);
    rtc.dayOfMonth = @intCast(tm.tm_mday);
    rtc.month = @intCast(tm.tm_mon + 1);
    rtc.year = @intCast(@rem(tm.tm_year, 100));

    const rtcU8 = cast.toPtr([*]u8, &rtc);

    if (rtcCenturyReg) |century| {
        rtcU8[century] = cast.u8(19 + cast.toInt(tm.tm_year) / 100);
    }

    pasteRtc(&rtc);
}

fn rtcGet(clock : *time.Clock) u64 {
    _ = clock;
    return time.timeToUnix(getRtc()).get(.SEC, false);
}

fn rtcSet(clock : *time.Clock, count : u64) void {
    _ = clock;
    setRtc(time.unixToTime(.Sec(count)));
}

fn setupRtc() void {
    var fadt : *acpica.ACPI_TABLE_FADT = undefined;
    if (acpica.ACPI_SUCCESS(acpica.AcpiGetTable(@constCast(@ptrCast(acpica.ACPI_SIG_FADT)), 0, @ptrCast(&fadt)))) {
        if (fadt.Century > 0) {
            rtcCenturyReg = fadt.Century;
        }
    }

    rtcMap = cast.toPtr(*Cmos, &copyRtc());
    rtcMap.regB.fmt = 1;

    const clock = kernel.pmalloc(time.Clock);
    time.Clock.CLOCKS.insertFront(&clock.link);

    clock.tps = 1;
    clock.getRaw = rtcGet;
    clock.setRaw = rtcSet;

    @memcpy(clock.name[0..3], "RTC");

    ports.out(Cmos.PORT_OUT, cast.u8(@offsetOf(Cmos, "regB")));
    var regB : Cmos.RegB = @bitCast(ports.in(Cmos.PORT_IN, u8));

    // 24-hour format only
    regB.fmt = 1;

    ports.out(Cmos.PORT_OUT, cast.u8(@offsetOf(Cmos, "regB")));
    ports.out(Cmos.PORT_IN, cast.bit(u8, regB));
}

pub fn setup() void {
    kernel.print("\narch: Setting up clocks and timers\n", .{});

    setupHpet();

    time.CALIBRATION_CLOCK = time.Clock.byName("HPET").?;

    setupTsc();
    setupLat();

    if (time.Clock.byName("TSC")) |tsc| {
        time.SYSTEM_CLOCK = tsc;
    }
    else {
        time.SYSTEM_CLOCK = time.Clock.byName("HPET").?;
    }

    if (time.Timer.byName("TSC")) |tsc| {
        time.LOCAL_TIMER = tsc;
    }
    else if (time.Timer.byName("LAT")) |lat| {
        time.LOCAL_TIMER = lat;
    }
    else {
         @panic("No per-core timer was available!");
    }

    setupRtc();

    if (time.Clock.byName("RTC")) |rtc| {
        time.setUnixClock(rtc.get());
    }
}