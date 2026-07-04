const kernel = @import("kernel");

pub const MAX_NUM_CPUS : u64 = 64;

pub const MAX_MEMORY_REGIONS : u64 = 1024;
pub const MIN_BUDDY_ORDER : u8 = 11; // Size 8 MB
pub const PER_CPU_PAGE_NUM = 32;
pub const IRQ_STACK_SIZE = kernel.util.types.SIZE_16KB;

pub const SCHED_PRIORITY_MAX = 32;
pub const ROUND_ROBIN_TIMESLICE = kernel.Time.create(.MSEC, 100);