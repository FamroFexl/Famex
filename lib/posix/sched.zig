const times = @import("times.zig");

pub const sched_param = extern struct {
    sched_priority : i32,                   // Process or thread execution scheduling priority.
    sched_ss_low_priority : i32,            // Low scheduling priority for sporadic server.
    sched_ss_repl_period : times.timespec,  // Replenishment period for sporadic server.
    sched_ss_init_budget : times.timespec,  // Initial budget for sporadic server.
    sched_ss_max_repl : i32,                // Maximum pending replenishments for sporadic server.
};