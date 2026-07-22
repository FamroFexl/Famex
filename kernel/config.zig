const kernel = @import("kernel");
const types = kernel.types;

pub const MAX_NUM_CPUS : u64 = 64;

pub const MAX_MEMORY_REGIONS : u64 = 1024;
pub const MIN_BUDDY_ORDER : u8 = 11; // Size 8 MB
pub const PER_CPU_PAGE_NUM = 32;
pub const IRQ_STACK_SIZE = types.SIZE_16KB;
pub const SYSCALL_STACK_SIZE = types.SIZE_16KB;

pub const SCHED_PRIORITY_MAX = 32;
pub const ROUND_ROBIN_TIMESLICE = kernel.Time.create(.MSEC, 100);

/// Buffer between the end of the stack and other VMAs
pub const USER_STACK_GUARD_GAP = types.SIZE_1MB;
/// The default max fault distance a stack error can be from the stack
/// in order to be considered legitimate
pub const USER_STACK_DEF_MAX_FAULT = 256;
/// The default max size of a user stack.
pub const USER_STACK_DEF_MAX_SIZE = types.SIZE_8MB;