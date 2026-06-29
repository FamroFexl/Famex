#pragma once
#define atomic_thread_fence(order) __c11_atomic_thread_fence(order)
#define smp_wmb() atomic_thread_fence(memory_order_release)
#define smp_rmb() atomic_thread_fence(memory_order_acquire)
#define unlikely(x) __builtin_expect(!!(x), 0)
#define likely(x)   __builtin_expect(!!(x), 1)

#define DIV_ROUND_UP(n, d) (((n) + (d) - 1) / (d))

#define NULL ((void*)0)

#define fallthrough

#define SINGLE_DEPTH_NESTING 1

#define BITS_PER_LONG 64

#define __rcu

typedef unsigned int u32;
typedef unsigned long long size_t;
typedef unsigned char u8;
typedef size_t u64;
typedef unsigned short u16;
typedef char bool;
#define true 1
#define false 0

#define nullptr ((void*)0)

typedef size_t rcu_free_t[2];
typedef bool spinlock_t;

typedef void slub_pool_t;

#define offsetof(type, member) ((size_t)&(((type *)0)->member))

// Pointer to a container from a container element
#define container_of(ptr, type, member) ((type *)((u8 *)(ptr) - offsetof(type, member)))

#define SPINLOCK_INIT(lock) lock = 0;

#define array_len(arr) (sizeof(arr) / sizeof((arr)[0]))

#define U64_MAX (unsigned long long)-1

#define SET_BIT(bit) ((1ULL) << (bit))
#define SET_BITS(amount) ((SET_BIT(amount)) - 1)

#define spinlock_held(lock) _spinlock_held(&lock)

extern void  spin_lock(void* lock);
extern void  spin_unlock(void* lock);
extern void  _spinlock_held(void* lock);
extern void* __rcu_set(void** ptr, void* val);
extern void* __rcu_get(void** ptr);
#define rcu_set(ptr, val) __rcu_set((void**) &(ptr), val)
#define rcu_get(ptr) __rcu_get(&(ptr))
extern void* slub_alloc(void* pool);
extern void slub_free(void* addr);
extern void rcu_read_lock();
extern void rcu_read_unlock();
extern void slub_rcu_async_free(rcu_free_t* free);
extern slub_pool_t* maple_pool_create(u64 size, u16 alignment);
extern slub_pool_t* xa_pool_create(u64 size, u16 alignment);

#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))

#define DEBUG_ASSERT(expr, fmt)

#define load_once(x) (*(volatile typeof(x) *)&(x))
#define store_once(x, v) (*(volatile typeof(x) *)&(x) = (v))

static void* memcpy(void* restrict dest, const void* restrict src, size_t size) {
    char* restrict pdest = dest;
    const char* restrict psrc = src;

    for (size_t i = 0; i < size; i++) {
        pdest[i] = psrc[i];
    }

    return dest;
}

static void *memmove(void* dest, const void* src, size_t size) {
    if (dest == src || size == 0)
        return dest;

    char* pdest = dest;
    const char* psrc = src;

    if (src > dest) {
        for (size_t i = 0; i < size; i++) {
            pdest[i] = psrc[i];
        }
    } else {
        for (size_t i = size; i > 0; i--) {
            pdest[i - 1] = psrc[i - 1];
        }
    }

    return dest;
}

static void* memset(void* s, char c, size_t size) {
    char* p = s;
    for (size_t i = 0; i < size; i++) {
        p[i] = c;
    }

    return s;
}

typedef enum {
    memory_order_relaxed = __ATOMIC_RELAXED,
    memory_order_consume = __ATOMIC_CONSUME,
    memory_order_acquire = __ATOMIC_ACQUIRE,
    memory_order_release = __ATOMIC_RELEASE,
    memory_order_acq_rel = __ATOMIC_ACQ_REL,
    memory_order_seq_cst = __ATOMIC_SEQ_CST
} memory_order;

#define atomic_load_explicit(obj, order) __c11_atomic_load((_Atomic(__typeof__(*(obj)))*)obj, order)
#define atomic_load(obj) atomic_load_explicit(obj, memory_order_seq_cst)

#define atomic_fetch_or_explicit(obj, operand, order) __c11_atomic_fetch_or((_Atomic(__typeof__(*(obj)))*)obj, operand, order)
#define atomic_fetch_or(obj, operand) atomic_fetch_or_explicit(obj, operand, memory_order_seq_cst)

#define atomic_fetch_and_explicit(obj, operand, order) __c11_atomic_fetch_and((_Atomic(__typeof__(*(obj)))*)obj, operand, order)
#define atomic_fetch_and(obj, operand) atomic_fetch_and_explicit(obj, operand, memory_order_seq_cst)

static void atomic_bit_set(u64 flag, void* flags) {
    u64* word = &flags[flag / 64];
    atomic_fetch_or(word, SET_BIT(flag % 64));
}

static bool atomic_bit_get_and_set(u64 flag, void* flags) {
    u64* word = &flags[flag / 64];
    size_t mask = SET_BIT(flag % 64);
    return atomic_fetch_or(word, mask) & mask;
}

static void atomic_bit_clear(u64 flag, void* flags) {
    u64* word = &flags[flag / 64];
    atomic_fetch_and(word, ~SET_BIT(flag % 64));
}

static bool atomic_bit_get_and_clear(u64 flag, void* flags) {
    u64* word = &flags[flag / 64];
    size_t mask = SET_BIT(flag % 64);
    return atomic_fetch_and(word, ~mask) & mask;
}

static bool atomic_bit_get(u64 flag, void* flags) {
    u64* word = &flags[flag / 64];
    size_t mask = SET_BIT(flag % 64);
    return atomic_load(word) & mask;
}

#define RCU_INIT_POINTER(ptr, val) rcu_set(ptr, val)

#define MAX_ERRNO 4095

#define compiletime_assert(condition, msg) do { } while (0)

#define __scalar_type_to_expr_cases(type)				\
unsigned type:	(unsigned type)0,			\
signed type:	(signed type)0

#define __unqual_scalar_typeof(x) typeof(				\
_Generic((x),						\
u8:	(u8)0,				\
__scalar_type_to_expr_cases(u8),		\
__scalar_type_to_expr_cases(u16),		\
__scalar_type_to_expr_cases(u32),		\
__scalar_type_to_expr_cases(u64),		\
default: (x)))

#define __native_word(t) \
(sizeof(t) == sizeof(u8) || sizeof(t) == sizeof(u16) || \
sizeof(t) == sizeof(u32) || sizeof(t) == sizeof(u64))

enum ERROR_NUM
{
    // No error with number 0, because it can't be negative
    E2BIG = 1,          // Argument list too long
    EACCES,             // Permission denied
    EADDRINUSE,         // Address in use
    EADDRNOTAVAIL,      // Address not available
    EAFNOSUPPORT,       // Address family not supported
    EAGAIN,             // Resource unavailable, try again (may be the same value as [EWOULDBLOCK])
    EALREADY,           // Connection already in progress
    EBADF,              // Bad file descriptor
    EBADMSG,            // Bad message
    EBUSY,              // Device or resource busy
    ECANCELED,          // Operation canceled
    ECHILD,             // No child processes
    ECONNABORTED,       // Connection aborted
    ECONNREFUSED,       // Connection refused
    ECONNRESET,         // Connection reset
    EDEADLK,            // Resource deadlock would occur
    EDESTADDRREQ,       // Destination address required
    EDOM,               // Mathematics argument out of domain of function
    EDQUOT,             // Reserved
    EEXIST,             // File exists
    EFAULT,             // Bad address
    EFBIG,              // File too large
    EHOSTUNREACH,       // Host unreachable
    EIDRM,              // Identifier removed
    EILSEQ,             // Illegal byte sequence
    EINPROGRESS,        // Operation in progress
    EINTR,              // Interrupted function
    EINVAL,             // Invalid argument
    EIO,                // I/O error
    EISCONN,            // Socket is disconnected
    EISDIR,             // Is a directory
    ELOOP,              // Too many levels of symbolic links
    EMFILE,             // File descriptor value too large
    EMLINK,             // Too many hard links
    EMSGSIZE,           // Message too large
    EMULTIHOP,          // Reserved
    ENAMETOOLONG,       // Filename too long
    ENETDOWN,           // Network is down
    ENETRESET,          // Connection aborted by network
    ENETUNREACH,        // Network unreachable
    ENFILE,             // Too many files open in system
    ENOBUFS,            // No buffer space available
    ENODEV,             // No such device
    ENOENT,             // No such file or directory
    ENOEXEC,            // Executable file format error
    ENOLCK,             // No locks available
    ENOLINK,            // Reserved
    ENOMEM,             // Not enough space
    ENOMSG,             // No message of the desired type
    ENOPROTOOPT,        // Protocol not available
    ENOSPC,             // No space left on device
    ENOSYS,             // Functionality not supported
    ENOTCONN,           // The socket is not connected
    ENOTDIR,            // Not a directory or a symbolic link to a directory
    ENOTEMPTY,          // Directory not empty
    ENOTRECOVERABLE,    // State not recoverable
    ENOTSOCK,           // Not a socket
    ENOTSUP,            // Not supported (may be the same value as [EOPNOTSUPP])
    ENOTTY,             // Inappropriate I/O control operation
    ENXIO,              // No such device or address
    EOPNOTSUPP,         // Operation not supported on socket (may be the same value as [ENOTSUP])
    EOVERFLOW,          // Value too large to be stored in a data type
    EOWNERDEAD,         // Previous owner died
    EPERM,              // Operation not permitted
    EPIPE,              // Broken pipe
    EPROTO,             // Protocol error
    EPROTONOSUPPORT,    // Protocol not supported
    EPROTOTYPE,         // Protocol wrong type for socket
    ERANGE,             // Result too large
    EROFS,              // Read-only file system
    ESOCKTNOSUPPORT,    // Socket type not supported
    ESPIPE,             // Invalid seek
    ESRCH,              // No such process
    ESTALE,             // Reserved
    ETIMEDOUT,          // Connection timed out
    ETXTBSY,            // Text file busy
    EWOULDBLOCK,        // Operation would block (may be the same value as [EAGAIN])
    EXDEV               // Improper hard link
};