// Local APIC Register Access Map
pub const ApicRegMap = packed struct(u1024) { // Every 32-bits has 128-bits of alignment
    __reserved1 : [4]u64,
    lapic_id : [2]u64,      // Local APIC ID Register (Read-Only)
    lapic_ver : [2]u64,     // Local APIC Version Register (Read-Only)
    __reserved2 : [8]u64,
    tpr : [2]u64,           // (TPR) Task Priority Register (Read/Write)
    apr : [2]u64,           // (APR) Arbitration Priority Register (Read-Only) (Impl-Dependant)
    ppr : [2]u64,           // (PPR) Processor Priority Register (Read-Only)
    eoi : [2]u64,           // (EOI) End Of Interrupt Register (Write-Only)
    rrd : [2]u64,           // (RRD) Remote Read Register (Read-Only) (Impl-Dependant)
    ldr : [2]u64,           // Logical Destination Register (Read/Write) (Read-Only in x2APIC)
    dfr : [2]u64,           // Destination Format Register (Read/Write) (xAPIC-only)
    svr : [2]u64,           // Spurious Interrupt Vector Register (Read/Write)
    isr : [16]u64,          // (ISR) In-Service Register (Read-Only)
    tmr : [16]u64,          // (TMR) Trigger Mode Register (Read-Only)
    irr : [16]u64,          // (IRR) Interrupt Request Register (Read-Only)
    esr : [2]u64,           // Error Status Register (Read/Write)
    __reserved3 : [12]u64,
    lvt_cmci : [2]u64,      // (CMCI) LVT Corrected Machine Check Interrupt Register (Read/Write)
    icr : [4]u64,           // (ICR) Interrupt Command Register (Read/Write)
    lvt_timer : [2]u64,     // LVT Timer Register (Read/Write)
    lvt_ts : [2]u64,        // LVT Thermal Sensor Register (Read/Write) (Impl-Dependant)
    lvt_pmc : [2]u64,       // LVT Performance Monitoring Counters Register (Read/Write) (Impl-Dependant)
    lvt_lint0 : [2]u64,     // LVT LINT0 Register (Read/Write)
    lvt_lint1 : [2]u64,     // LVT LINT1 Register (Read/Write)
    lvt_err : [2]u64,       // LVT Error Register (Read/Write)
    timer_ic : [2]u64,      // Initial Count Register (for Timer) (Read/Write)
    timer_cc : [2]u64,      // Current Count Register (for Timer) (Read-Only)
    __reserved4 : [8]u64,
    timer_dc : [2]u64,      // Divide Configuration Register (for Timer) (Read/Write)
    self_ipi : [2]u64,      // Self IPI Register (Write-Only) (x2APIC-Only)
};

pub const LapicVerReg = packed struct(u32) {
    version : u8,           // Version numbers of Local APIC (0x0) 82489DX discreet APIC (0x10-0x15) Integrated APIC
    __pad : u8,
    max_lvt_entry : u8,     // Local Vector Table max entries to configure local interrupts
    eoi_suppression : bool, // Can software stop EOI messaging
};

pub const LapicIDReg = packed struct(u32) {
    __pad : u24,
    apic_id : u8,
};

// A Local Vector Table register
pub const LvtReg = packed struct(u32) {
    vector              : u8,               // LVT number
    delivery_mode       : DeliveryMode,     // Interrupt type to be sent (not for lvt_err)
    __pad               : u1,
    delivery_status     : u1,               // (0) No interrupt pending, (1) Interrupt is pending at processor

    // For LVT_LINT0 or LVT_LINT1 only
    int_pin_polarity    : u1,               // (0) Active high, (1) Active low
    remote_irr          : u1,               // Set when an interrupt is being serviced
    trigger_mode        : u1,               // (0) Edge-sensitive, (1) Level Sensitive

    mask                : u1,               // (0) Interrupt reception, (1) Inhibits reception
    // Intel defines 2 bits for support of TSC_DEADLINE. AMD only has single bit.
    timer_mode          : TimerMode,        // Timer mode (for lvt_timer only)

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
    send_checksum   : bool,    // Send Checksum (not used)
    recv_checksum   : bool,    // Receive Checksum (not used)
    send_accept     : bool,    // Send Accept (not used)
    recv_accept     : bool,    // Receive Accept (not used)
    redir_ipi       : bool,    // Redirectable IPI
    send_ill_vec    : bool,    // Send Illegal Vector
    recv_ill_vec    : bool,    // Receive Illegal Vector
    ill_vec_addr    : bool,    // Illegal Register Address
};

// Interrupt Command Register (used for IPIs)
pub const IcrReg = packed struct(u64) {
    vector          : u8,
    delivery_mode   : u3,
    dest_mode       : DestMode,         // Interrupt type to be sent
    delivery_status : u1,               // (0) No interrupt pending, (1) Interrupt is pending at processor (not used in x2apic)
    __pad           : u1,
    level           : u1,               // (0) De-Assert, (1) Assert
    trigger_mode    : TriggerMode,      // (0) Edge-sensitive, (1) Level Sensitive (when using DMODE_INIT)
    __pad2          : u2,
    dest_shorthand  : DestShorthand,    // Optional shorthand used for destination
    __pad3          : u12,
    //Only the top 8 bits contain the ID if x2apic is enabled
    dest_field      : u32,              // Destination Processor by APIC ID (physical) or MDA (logical)

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
    __pad       : u24,
    log_apic_id : u8,    // Logical APIC ID
};

// Destination Format Register
pub const DfrReg = packed struct(u32) {
    __pad : u28,
    model : DfrModel,

    pub const DfrModel = enum(u4) {
        CLUSTER = 0,
        FLAT = 15,
    };
};

// Generic Priority Register (TPR, APR, PPR)
pub const PrioReg = packed struct(u32) {
    sub_class   : u4,
    prio_class  : u4,
};

// Timer Divide Configuration Register
pub const TimerDcReg = packed struct(u32) {
    div_val : DivideValue,
    __pad : u28,

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
    __pad : u16,
    vec1 : u48,   // Pending vectors
    vec2 : u64,
    vec3 : u64,
    vec4 : u64,
};

// Spurious Interrupt Vector Register
pub const SvrReg = packed struct(u64) {
    vector      : u8,    // Spurious Vector
    apic_on     : bool,    // APIC Software (0) disable, (1) enable
    fpc         : bool,    // Focused Processor Checking
    __pad       : u2,
    eoi_supr    : bool,    // EIO-Broadcast Suppression
};