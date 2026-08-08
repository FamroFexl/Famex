const unistd = @import("unistd.zig");

fn min(num1 : anytype, num2: anytype) u64 {
    return if (num1 > num2) num2 else num1;
}

fn max(num1 : anytype, num2: anytype) u64 {
    return if (num1 > num2) num1 else num2;
}

pub const RTSIG_MAX = max(unistd._POSIX_RTSIG_MAX, 32);
pub const SIGQUEUE_MAX = max(unistd._POSIX_SIGQUEUE_MAX, 32);
pub const TIMER_MAX = max(unistd._POSIX_TIMER_MAX, 32);
pub const DELAYTIMER_MAX = max(unistd._POSIX_DELAYTIMER_MAX, 32);