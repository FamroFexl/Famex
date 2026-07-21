#include <asm_offsets.h>

.code64
.intel_syntax noprefix

.section .entry.text, "ax"

.macro EXCP_TBL from, to
    .pushsection .excp_tbl, "a"
    .balign 8
    .quad \from
    .quad \to
    .popsection
.endmacro

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

/*
 * Uses stack to determine if a state is in kernel mode.
 *
 * RDI must point to a CpuState
 */
FUNC inKmode
    mov rdi, [rdi + RSP_OFST]
    test rdi, rdi
    js end
        mov rax, 0
        ret
    end:
    mov rax, 1
    ret
FUNC_END inKmode

FUNC getCr0
    mov rax, cr0
    ret
FUNC_END getCr0

FUNC setCr0
    mov cr0, rdi
    ret
FUNC_END setCr0

FUNC getCr2
    mov rax, cr2
    ret
FUNC_END getCr2

FUNC getCr3
    mov rax, cr3
    ret
FUNC_END getCr3

FUNC setCr3
    mov cr3, rdi
    ret
FUNC_END setCr3

FUNC getCr4
    mov rax, cr4
    ret
FUNC_END getCr4

FUNC setCr4
    mov cr4, rdi
    ret
FUNC_END setCr4

FUNC getCr8
    mov rax, cr8
    ret
FUNC_END getCr8

FUNC setCr8
    mov cr8, rdi
    ret
FUNC_END setCr8

FUNC getXCr
    mov ecx, edi
    xgetbv
    shl rdx, 32
    or rax, rdx
    ret
FUNC_END getXCr

FUNC setXCr
    mov ecx, edi
    mov rdx, rsi
    shr rdx, 32
    mov rax, rsi
    xsetbv
    ret
FUNC_END setXCr

FUNC fxSave
    fxsave [rdi]
    ret
FUNC_END fxSave

FUNC fxLoad
    fxrstor [rdi]
    ret
FUNC_END fxLoad

FUNC xSave
    mov eax, -1
    mov edx, -1
    xsave [rdi]
    ret
FUNC_END xSave

FUNC xLoad
    mov eax, -1
    mov edx, -1
    xrstor [rdi]
    ret
FUNC_END xLoad

FUNC fpStateReset
    fninit
    sub rsp, 8
    mov qword ptr [rsp], 0x1F80
    ldmxcsr [rsp]
    add rsp, 8
    ret
FUNC_END fpStateReset

FUNC getRflags
    pushfq
    pop rax
    ret
FUNC_END getRflags

FUNC setRflags
    push rdi
    popfq
    ret
FUNC_END setRflags

FUNC getMsr
    mov ecx, edi
    rdmsr
    shl rdx, 32
    or rax, rdx
    ret
FUNC_END getMsr

FUNC setMsr
    mov ecx, edi
    mov rdx, rsi
    shr rdx, 32
    mov rax, rsi
    wrmsr
    ret
FUNC_END setMsr

FUNC getGdtr
    sgdt [rdi]
    ret
FUNC_END getGdtr

FUNC setGdtr
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
FUNC_END setGdtr

FUNC getIdtr
    sidt [rdi]
    ret
FUNC_END getIdtr

FUNC setIdtr
    lidt [rdi]
    ret
FUNC_END setIdtr

FUNC getTss
    str ax
    ret
FUNC_END getTss

FUNC setTss
    ltr di
    ret
FUNC_END setTss

FUNC getTsc
    rdtsc
    shl rdx, 32
    or rax, rdx
    ret
FUNC_END getTsc

FUNC tlbPageFlush
    invlpg [rdi]
    ret
FUNC_END tlbPageFlush

FUNC spinWaitLoop
    pause
    ret
FUNC_END spinWaitLoop

FUNC idleEntry
    1:
    sti
    hlt
    jmp 1b
FUNC_END idleEntry

FUNC irqEnable
    sti
    ret
FUNC_END irqEnable

FUNC irqDisable
    cli
    ret
FUNC_END irqDisable

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
FUNC saveRegs
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
FUNC_END saveRegs

/*
 * RDI must point to a cpu state
 *
 * Must execute after swapgs in (kernel state)
 *
 * Output: All registers as defined in cpu state
*/
FUNC loadRegs
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
FUNC_END loadRegs

/*
 * RDI must point to a CpuState
 *
 * Returns true if saving, false if loading
 */
.globl bpoint1
FUNC saveState
    // Returned when loading
    mov rax, 0

    // Dummy RDI to satisfy save_regs requirements
    push rdi
    call saveRegs

    // Returned when saving
    mov rax, 1

    // Save RFLAGS
    pushfq
    pop rsi
    mov [rdi + RFLAGS_OFST], rsi

    // Save RSP
    mov [rdi + RSP_OFST], rsp

    /**
     * This function returns twice, once when saving,
     * and once when loading, so we need two  of the
     * same return address
     */
    mov rsi, [rsp]
    push rsi

    // Save current RIP
    lea rsi, [rip + 1f]
    mov [rdi + RIP_OFST], rsi
    1:

    ret
FUNC_END saveState

/*
 * RDI must point to a CpuState
 */
FUNC loadState
    // Setup interrupt frame for return

    push rdi

    // Stack: rdi

    // RDI contains cpu_state, as required by in_kmode
    call inKmode

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

    call loadRegs

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

    bpoint12:

    iretq
FUNC_END loadState

/*
 * Copy bytes with exception handling
 *
 * RDI points to destination
 * RSI points to source
 * RDX contains length
 */
FUNC memcpyExcp
    mov rcx, rdx

0:  rep movsb

1:  mov rax, rcx
    ret

    EXCP_TBL 0b, 1b
FUNC_END memcpyExcp
