pub const Prio = enum(i32) {
    PRIO_PROCESS = 0,   // Identifies the who argument as a process ID.
    PRIO_PGRP = 1,      // Identifies the who argument as a process group ID.
    PRIO_USER = 2,      // Identifies the who argument as a user ID.
};

pub const RLimit = enum(i32) {
    RLIMIT_CORE = 0,        // Limit on size of core image.
    RLIMIT_CPU = 1,         // Limit on CPU time per process.
    RLIMIT_DATA = 2,        // Limit on data segment size.
    RLIMIT_FSIZE = 3,       // Limit on file size.
    RLIMIT_NOFILE = 4,      // Limit on number of open files.
    RLIMIT_STACK = 5,       // Limit on stack size.
    RLIMIT_AS = 6,          // Limit on address space size.
    _,
};

pub const rlim_t = u32;

pub const rlimit = extern struct {
    rlim_cur : rlim_t,  // The current (soft) limit.
    rlim_max : rlim_t,  // The hard limit.
};