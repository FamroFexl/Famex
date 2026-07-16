.code64
.intel_syntax noprefix

.section .rodata
msg:
    .asciz "Hello, world!"

msg2:
    .asciz "Greetings!"

.section .text.entry, "ax"

.macro FUNC name
.globl \name
.type \name, @function
\name:
.endmacro

.macro FUNC_END name
.size \name, .-\name
.endmacro

.extern main

FUNC _start
    xor rbp, rbp

    and rsp, -16

    mov rax, 1
    lea rdi, [rip + msg]
    syscall

    mov rax, 1
    lea rdi, [rip + msg]
    syscall
1:
    jmp 1b
FUNC_END _start

// return RAX
// arguments RDI, RSI, RDX, RCX, R8, R9