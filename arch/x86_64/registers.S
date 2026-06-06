.code64
.intel_syntax noprefix

.section .entry.text, "ax"

// RAX
// RDI, RSI, RDX, RCX, R8, R9

.globl get_cr3
.type get_cr3, @function
get_cr3:
    mov rax, cr3
    ret

.globl set_cr3
.type set_cr3, @function
set_cr3:
    mov cr3, rdi
    ret
