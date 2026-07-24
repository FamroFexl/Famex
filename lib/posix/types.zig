pub const dev_t = u32;
pub const key_t = u32;

// Must be able to individually store a pid_t, uid_t, or gid_t
pub const id_t = u32;

// Must be signed
pub const pid_t = i32;

// These NEED to be signed (for some reason, POSIX is ambiguous!)
// They will be set to negative values in syscalls.
pub const uid_t = i32;
pub const gid_t = i32;

pub const pthread_attr_t = extern struct {
    detached : bool,                // Created detached (joinable if false)
    guard_size : u64,           // Stack buffer overflow guard memory size
    inherit_sched : bool,           // Inherit sched (explicit if false)
    //struct sched_param params;    // Scheduler parameters
    sched_policy : i32,             // Scheduler policy
    system_scope : bool,            // System contention scope (process contention scope if false)
    stack_addr : *anyopaque,        // Address of the thread stack
    stack_size : u64,               // Size of the thread stack
};


// typedef pthread_barrier_t
// typedef pthread_barrierattr_t
// typedef pthread_cond_t
// typedef pthread_condattr_t
// typedef pthread_key_t

pub const pthread_mutexattr_t = extern struct {
    prioceiling : i32,  // Priority ceiling
    protocol : u8,      // Protocol to be used
    pshared : bool,     // Shared between processes (private if false)
    robust : bool,      // Robust mutex (stalled if false)
    type : u8,
};

pub const pthread_spinlock_t = bool;

pub const pthread_mutex_t = extern struct {
    attr : pthread_mutexattr_t,
    lock : pthread_spinlock_t,
    owner : *anyopaque,         // Owner thread
};

// typedef pthread_once_t
// typedef pthead_rwlock_t
// typedef pthread_rwlockattr_t

pub const mode_t = u64;
pub const nlink_t = u64;
pub const reclen_t = u64;
pub const off_t = u64;
pub const ino_t = u64;
pub const blkcnt_t = i64;
pub const blksize_t = i64;
pub const fsblkcnt_t = u64;
pub const fsfilcnt_t = u64;

pub const clock_t = u64;
pub const clockid_t = u32;
pub const suseconds_t = i64;
pub const time_t = u64;
pub const timer_t = u64;

pub const ssize_t = i64;