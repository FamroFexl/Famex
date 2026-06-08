#include <asm_offsets.h>

.code64
.intel_syntax noprefix

.section .entry.text, "ax"

.extern in_kmode

.macro FUNC name
.globl \name
.type \name, @function
\name:
.endmacro

.macro FUNC_END name
.size \name, .-\name
.endmacro

// return RAX
// arguments RDI, RSI, RDX, RCX, R8, R9

FUNC get_cr0
    mov rax, cr0
    ret
FUNC_END get_cr0

FUNC set_cr0
    mov cr0, rdi
    ret
FUNC_END set_cr0

FUNC get_cr2
    mov rax, cr2
    ret
FUNC_END get_cr2

FUNC get_cr3
    mov rax, cr3
    ret
FUNC_END get_cr3

FUNC set_cr3
    mov cr3, rdi
    ret
FUNC_END set_cr3

FUNC get_cr4
    mov rax, cr4
    ret
FUNC_END get_cr4

FUNC set_cr4
    mov cr3, rdi
    ret
FUNC_END set_cr4

FUNC get_cr8
    mov rax, cr8
    ret
FUNC_END get_cr8

FUNC set_cr8
    mov cr8, rdi
    ret
FUNC_END set_cr8

FUNC get_rflags
    pushfq
    pop rax
    ret
FUNC_END get_rflags

FUNC set_rflags
    push rdi
    popfq
    ret
FUNC_END set_rflags

FUNC get_msr
    mov ecx, edi
    rdmsr
    shl rdx, 32
    or rax, rdx
    ret
FUNC_END get_msr

FUNC set_msr
    mov ecx, edi
    mov rdx, rsi
    shr rdx, 32
    mov rax, rsi
    wrmsr
    ret
FUNC_END set_msr

FUNC get_gdt
    sgdt [rax]
    ret
FUNC_END get_gdt

FUNC set_gdt
    lgdt [rdi]
    mov ax, KMODE_DATA_OFST
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    push KMODE_CODE_OFST
    lea rax, [rip + 1f]
    push rax
    retfq
    1:
    ret
FUNC_END set_gdt

FUNC get_idt
    sidt [rax]
    ret
FUNC_END get_idt

FUNC set_idt
    lidt [rdi]
    ret
FUNC_END set_idt

FUNC get_tss
    str ax
    ret
FUNC_END get_tss

FUNC set_tss
    ltr di
    ret
FUNC_END set_tss

FUNC get_tsc
    rdtsc
    shl rdx, 32
    or rax, rdx
    ret
FUNC_END get_tsc

FUNC tlb_page_flush
    invlpg [rdi]
    ret
FUNC_END tlb_page_flush

FUNC spin_wait_loop
    pause
    ret
FUNC_END spin_wait_loop

FUNC idle_entry
    sti
    hlt
FUNC_END idle_entry

FUNC irq_enable
    sti
    ret
FUNC_END irq_enable

FUNC irq_disable
    cli
    ret
FUNC_END irq_disable

/*
 * Because this is called, the RDI pushed to the stack is buried beneath the ret value, so we must
 * pop off the return, grab the RDI, and push the return
 *
 * u64 stack[0] must point to previous RDI
 * RDI must point to a cpu state
 * Must execute after swapgs in (kernel state)
 *
 * Output: All registers same out as in. u64 stack[0] is consumed.
*/
FUNC save_regs
    // Save rax so we can use it as a scratch register
    mov [rdi + RAX_OFST], rax

    // Pop return value
    pop rax
    // Pop RDI and save
    pop qword ptr [rdi + RDI_OFST]
    // Restore return value
    push rax

    mov [rdi + RBX_OFST], rbx
    mov [rdi + RCX_OFST], rcx
    mov [rdi + RDX_OFST], rdx
    mov [rdi + RSI_OFST], rsi
    mov [rdi + RBP_OFST], rbp
    mov [rdi + R8_OFST],  r8
    mov [rdi + R9_OFST],  r9
    mov [rdi + R10_OFST], r10
    mov [rdi + R11_OFST], r11
    mov [rdi + R12_OFST], r12
    mov [rdi + R13_OFST], r13
    mov [rdi + R14_OFST], r14
    mov [rdi + R15_OFST], r15

    // Get User FS Base
    mov ecx, FS_BASE
    rdmsr
    mov [rdi + FS_BASE_OFST],       eax
    mov [rdi + FS_BASE_OFST + 4],   edx

    // Get User GS Base
    // Because swapgs occurred, the user GS Base is in Kernel_GS_Base
    // If saving a kernel thread, Kernel_GS_Base will contain garbage
    mov ecx, KERNEL_GS_BASE
    rdmsr
    mov [rdi + GS_BASE_OFST],       eax
    mov [rdi + GS_BASE_OFST + 4],   edx

    // Restore clobbered registers
    mov rax, [rdi + RAX_OFST]
    mov rcx, [rdi + RCX_OFST]
    mov rdx, [rdi + RDX_OFST]

    // We don't restore RDI since it didn't change

    ret
FUNC_END save_regs

/*
 * RDI must point to a cpu state
 *
 * Must execute after swapgs in (kernel state)
 *
 * Output: All registers as defined in cpu state
*/
FUNC load_regs
    // Set User FS Base
    mov ecx, FS_BASE
    mov eax, [rdi + FS_BASE_OFST]
    mov edx, [rdi + FS_BASE_OFST + 4]
    wrmsr

    // Set User GS Base
    // Because swapgs occurred, the user GS Base is in Kernel_GS_Base
    // If restoring a kernel thread, Kernel_GS_Base will contain garbage
    mov ecx, KERNEL_GS_BASE
    mov eax, [rdi + GS_BASE_OFST]
    mov edx, [rdi + GS_BASE_OFST + 4]
    wrmsr

    mov rax, [rdi + RAX_OFST]
    mov rbx, [rdi + RBX_OFST]
    mov rcx, [rdi + RCX_OFST]
    mov rdx, [rdi + RDX_OFST]
    mov rsi, [rdi + RSI_OFST]
    mov rbp, [rdi + RBP_OFST]
    mov r8,  [rdi + R8_OFST]
    mov r9,  [rdi + R9_OFST]
    mov r10, [rdi + R10_OFST]
    mov r11, [rdi + R11_OFST]
    mov r12, [rdi + R12_OFST]
    mov r13, [rdi + R13_OFST]
    mov r14, [rdi + R14_OFST]
    mov r15, [rdi + R15_OFST]

    // Restore RDI
    mov rdi, [rdi + RDI_OFST]

    ret
FUNC_END load_regs

FUNC save_state
    // Dummy RDI to satisfy save_regs requirements
    push rdi
    call save_regs

    // Save RFLAGS
    pushfq
    pop rsi
    mov [rdi + RFLAGS_OFST], rsi

    // Save RSP
    mov [rdi + RSP_OFST], rsp

    // Save current RIP (usually not used)
    call 1f
    1: pop [rdi + RIP_OFST]

    ret
FUNC_END save_state

FUNC load_state
    // Setup interrupt frame for return

    // Save stack
    mov rsi, rsp
    and rsp, -16
    push rdi
    push rsi

    // Stack: cpu_state, old_rsp

    // RDI contains cpu_state, as required by in_kmode
    call in_kmode

    // Restore stack
    pop rsi
    mov rsp, rsi

    // Stack: cpu_state

    // Restore rdi
    pop rdi

    // Stack:

    // Set correct segments
    mov r10, SS_0
    mov r11, CS_0

    cmp rax, 1
    je 1f
        mov r10, SS_3
        mov r11, CS_3
    1:

    // Push correct Data Segment
    push r10

    // Push RSP
    mov rdx, [rdi + RSP_OFST]
    push rdx

    // Push RFLAGS
    mov rdx, [rdi + RFLAGS_OFST]
    push rdx

    // Push correct Code Segment
    push r11

    // Push RIP
    mov rdx, [rdi + RIP_OFST]
    push rdx

    // Stack: data_seg, rsp, rflags, code_seg, rip

    // Save in_kmode
    push rax

    // Stack: data_seg, rsp, rflags, code_seg, rip, in_kmode

    call load_regs

    // Save new rax
    push rax

    // Stack: data_seg, rsp, rflags, code_seg, rip, in_kmode, rax

    // Use in_kmode to decide if swapgs is required
    mov rax, [rsp + 8]
    cmp rax, 1
    je 1f
        swapgs
    1:

    // Restore new rax
    pop rax

    // Stack: data_seg, rsp, rflags, code_seg, rip, in_kmode

    add rsp, 8

    // Stack: data_seg, rsp, rflags, code_seg, rip

    iretq
FUNC_END load_state
