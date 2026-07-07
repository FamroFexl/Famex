/*
 * ACPICA Modification for OS-support
 */

#ifndef __ACFAMEX_H__
#define __ACFAMEX_H__

#define ACPI_USE_LOCAL_CACHE 1

#define ACPI_MUTEX_TYPE ACPI_OSL_MUTEX

#define ACPI_MACHINE_WIDTH          64

#define ACPI_MISALIGNMENT_NOT_SUPPORTED

/*
 * Zig compatibility fixes
 */

#define ACPI_OFFSET(d, f) ((ACPI_SIZE)__builtin_offsetof(d, f))

#define FAMEX_PACKED __attribute__((packed))

#endif /* __ACFAMEX_H__ */