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
.extern syscallHandler

// C function for handling interrupts (arch specific)
.extern interruptVectorHandler

// Used to determine if a thread is in kernel mode
.extern inKmode

.extern saveRegs
.extern loadRegs

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
 // TODO update to support nested interrupts on ist stack entry
FUNC irqEntry
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
    call saveRegs

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
    call interruptVectorHandler

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

    call inKmode

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
    call loadRegs

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

FUNC_END irqEntry

/*
 * On entry, RCX contains the last RIP, R11 contains the last RFLAGS, and RSP contains
 * the last RSP.
 *
 * Certain registers can be clobbered since the general behavior of a syscall
 * is kernel-defined.
 *
 * Syscalls MUST only be called from user mode since this entry automatically
 * does a swapgs, which would corrupt the user segment in kernel mode.
 *
 * The c handler called by this entry must be of the following format:
 * void (*syscall_handler) (struct cpu_state*);
 *
 * On exit, RCX must contain the RIP to be loaded, R11 must contain the RFLAGS to be
 * loaded, RSP must contain the RSP to be loaded, and RAX must contain the return value
 */
FUNC syscallEntry
    /*
     * Switch to cpu_data for kernel-mode (needed for syscall_handler and getting the current
     * thread's kernel stack instance (KSTACKTOP)
     */
    swapgs

    // RSP is still set to the current user stack, which we need to save. RAX can be safely clobbered
    mov rax, rsp

    // Switch to kernel stack
    mov rsp, gs:[SYSCALL_STACK_OFST]

    // Alloc stack space and align (for SysV func alignment)
    sub rsp, CPU_STATE_SIZE
    and rsp, -16

    // Stack: cpu_state

    // Temp save RDI
    push rdi

    // Stack: cpu_state, old_rdi

    // Set rdi to cpu_state
    lea rdi, [rsp + 8]

    // Save user flags
    mov [rdi + RFLAGS_OFST], r11

    // Save user pc
    mov [rdi + RIP_OFST], rcx

    // Save user stack
    mov [rdi + RSP_OFST], rax

    // Save regs consumes old_rdi from stack
    call saveRegs

    // Stack: cpu_state

    // Set rdi back to cpu state
    lea rdi, [rsp]

    // Called with rdi arg
    call syscallHandler

    // Set rdi back to cpu_state
    lea rdi, [rsp]

    call loadRegs

    // Restore user flags
    mov r11, [rsp + RFLAGS_OFST]

    // Restore user pc
    mov rcx, [rsp + RIP_OFST]

    // Used as scratch reg to avoid modifying rsp directly
    mov rdi, [rsp + RSP_OFST]

    // Switch back to user thread state
    swapgs

    /*
     * We disable interrupts until RFLAGS switches back during sysret
     * so the user stack isn't scrambled by interrupts. This was suggested
     * by the Intel SDM.
     *
     * It is required to make sure an interrupt that executes between the user
     * stack being restored and sysret won't mistake the thread as in user mode.
     *
     * Generally, interrupts are enabled throughout the
     * syscall handler because syscalls are executing on behalf of threads,
     * and threads should be able to be preempted in user or kernel mode
     * regardless.
     */
    cli

    // Restore user stack
    mov rsp, rdi

    sysret

FUNC_END syscallEntry