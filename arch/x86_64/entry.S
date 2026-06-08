#include <asm_offsets.h>

.code64
.intel_syntax noprefix

.section .entry.text, "ax"

/*
 * Generally, the goal of most asm routines should be to transfer the burden to dedicated c
 * handlers as soon as possible. This avoids asm bugs in favor of c bugs, which are usually
 * easier to debug.
*/

// C function for handling system calls (generic)
.extern syscall_handler

// C function for handling interrupts (arch specific)
.extern interrupt_vector_handler

// Used to determine if a thread is in kernel mode
.extern in_kmode

.extern save_regs
.extern load_regs

.macro FUNC name
.globl \name
.type \name, @function
\name:
.endmacro

.macro FUNC_END name
.size \name, .-\name
.endmacro

/*
 * On entry, we have irq_frame and irq_num on stack (irq_num is pushed by a stub)
 *
 * The c handler called by this entry must be of the following format:
 * void (*irq_handler) (struct cpu_state*, u64, u64);
 *
 * Before the c handler, the current register contents are saved in a cpu_state
 * After the c handler, the current registers are set to the contents of the cpu_state
 *
 * On exit, only irq_frame can remain
 */
FUNC irq_entry
    // Stack: irq_frame, irq_num

    // Alloc stack space and align
    sub rsp, CPU_STATE_SIZE

    // Stack: irq_frame, irq_num, cpu_state

    // Temp save rdi as save_regs mandates
    push rdi

    // Stack: irq_frame, irq_num, cpu_state, rdi_save

    // Swapgs if not in kernel mode
    mov rdi, [rsp + 8 + CPU_STATE_SIZE + 8 + INT_SFRAME_CS]
    and rdi, 3
    cmp rdi, 0
    je 1f
        swapgs
    1:

    // Stack: irq_frame, irq_num, cpu_state, old_rdi

    // rdi will be cpu_state address, as save_regs mandates
    lea rdi, [rsp + 8]

    // Consumes rdi from stack
    call save_regs

    // Stack: irq_frame, irq_num, cpu_state

    // Transfer RFLAGS from frame into cpu_state
    mov rax, [rsp + CPU_STATE_SIZE + 8 + INT_SFRAME_RFLAGS]
    mov qword ptr [rsp + RFLAGS_OFST], rax

    // Transfer RIP from frame into cpu_state
    mov rax, [rsp + CPU_STATE_SIZE + 8 + INT_SFRAME_RIP]
    mov qword ptr [rsp + RIP_OFST], rax

    // Transfer RSP from frame into cpu_state
    mov rax, [rsp + CPU_STATE_SIZE + 8 + INT_SFRAME_RSP]
    mov qword ptr [rsp + RSP_OFST], rax

    // cpu_state is arg 1 (pointer arg)
    lea rdi, [rsp]

    // error code (if applicable)
    mov rsi, [rsp + 8 + CPU_STATE_SIZE]

    // irq_num is arg 3 (u64 arg)
    mov rdx, [rsp + CPU_STATE_SIZE]

    //mov rcx, [rsp + 8 + CPU_STATE_SIZE + INT_SFRAME_CS]

    // Save current rsp
    mov rbx, rsp

    // Align to SysV expectations on c function call
    and rsp, -16
    sub rsp, 8

    // Save last rsp on alignment
    push rbx

    // Stack: irq_frame, irq_num, cpu_state, last_rsp

    // Called with rdi, rsi, rdx args
    call interrupt_vector_handler

    // Restore last_rsp
    pop rbx
    mov rsp, rbx

    // Stack: irq_frame, irq_num, cpu_state

    // Transfer RFLAGS from cpu_state back into frame
    mov rax, [rsp + RFLAGS_OFST]
    mov qword ptr [rsp + CPU_STATE_SIZE + 8 + INT_SFRAME_RFLAGS], rax

    // Transfer RIP from cpu_state back into frame
    mov rax, [rsp + RIP_OFST]
    mov qword ptr [rsp + CPU_STATE_SIZE + 8 + INT_SFRAME_RIP], rax

    // Transfer RSP from cpu_state back into frame
    mov rax, [rsp + RSP_OFST]
    mov qword ptr [rsp + CPU_STATE_SIZE + 8 + INT_SFRAME_RSP], rax

    // RDI contains cpu_state, as required by in_kmode
    lea rdi, [rsp]

    // Save stack
    mov rsi, rsp
    and rsp, -16
    push rsi

    // Stack: irq_frame, irq_num, cpu_state, old_rsp

    call in_kmode

    // Restore stack
    pop rsi
    mov rsp, rsi

    // Stack: irq_frame, irq_num, cpu_state

    // Set cpu_state address for restore_regs
    lea rdi, [rsp]

    // Save in_kmode
    push rax

    // Stack: irq_frame, irq_num, cpu_state, in_kmode

    // After this call, we can only modify rflags, rip, and rsp
    call load_regs

    // Save new rax
    push rax

    // Stack: irq_frame, irq_num, cpu_state, in_kmode, rax

    // Move in_kmode to rax
    mov rax, [rsp + 8]

    // Set Data and Code Segments for return
    mov qword ptr [rsp + 16 + CPU_STATE_SIZE + 8 + INT_SFRAME_SS], SS_0
    mov qword ptr [rsp + 16 + CPU_STATE_SIZE + 8 + INT_SFRAME_CS], CS_0

    cmp rax, 0
    jne 1f
        mov qword ptr [rsp + 16 + CPU_STATE_SIZE + 8 + INT_SFRAME_SS], SS_3
        mov qword ptr [rsp + 16 + CPU_STATE_SIZE + 8 + INT_SFRAME_CS], CS_3
        swapgs
    1:

    // Restore rax
    pop rax

    // Stack: irq_frame, irq_num, cpu_state, in_kmode

    // Sanitize stack for return
    add rsp, 8 + CPU_STATE_SIZE + 8

    // Stack: irq_frame

    // Return from interrupt
    iretq

FUNC_END irq_entry