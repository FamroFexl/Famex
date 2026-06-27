/*
 * ACPICA Modification for OS-support
 */

#ifndef __ACCLANG_H__
#define __ACCLANG_H__

#define ACPI_INLINE             __inline__

/* Function name is used for debug output. Non-ANSI, compiler-dependent */

#define ACPI_GET_FUNCTION_NAME          __func__

/*
 * Some compilers complain about unused variables. Sometimes we don't want to
 * use all the variables (for example, _AcpiModuleName). This allows us
 * to tell the compiler warning in a per-variable manner that a variable
 * is unused.
 */
#define ACPI_UNUSED_VAR __attribute__ ((unused))

/* GCC supports __VA_ARGS__ in macros */

#define COMPILER_VA_MACRO

typedef __builtin_va_list va_list;

#define va_start(ap, argN)  __builtin_va_start(ap, argN)
#define va_copy(dest, src)  __builtin_va_copy(dest, src)
#define va_arg(ap, type)    __builtin_va_arg(ap, type)
#define va_end(ap)          __builtin_va_end(ap)

#endif /* __ACCLANG_H__ */