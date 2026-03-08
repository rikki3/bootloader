[BITS 64]

section .text
global kernel_entry
global interrupt_init
extern kernel_main
extern interrupt_handle
extern __bss_start
extern __bss_end

%macro ISR_NOERR 1
isr_stub_%1:
    push qword 0
    push qword %1
    jmp isr_common
%endmacro

%macro ISR_ERR 1
isr_stub_%1:
    push qword %1
    jmp isr_common
%endmacro

%macro SET_IDT 2
    lea rax, [rel %2]
    mov word [idt_table + (%1 * 16) + 0], ax
    mov word [idt_table + (%1 * 16) + 2], 0x08
    mov byte [idt_table + (%1 * 16) + 4], 0
    mov byte [idt_table + (%1 * 16) + 5], 0x8E
    shr rax, 16
    mov word [idt_table + (%1 * 16) + 6], ax
    shr rax, 16
    mov dword [idt_table + (%1 * 16) + 8], eax
    mov dword [idt_table + (%1 * 16) + 12], 0
%endmacro

kernel_entry:
    cli
    cld
    mov rax, cr0
    and rax, ~(1 << 2)
    or rax, (1 << 1)
    mov cr0, rax

    mov rax, cr4
    or rax, (1 << 9) | (1 << 10)
    mov cr4, rax

    fninit
    mov rbx, rdi
    mov rdi, __bss_start
    mov rcx, __bss_end
    sub rcx, rdi
    xor eax, eax
    rep stosb
    mov rsp, stack_top
    mov rbp, rsp
    call interrupt_init
    mov rdi, rbx
    call kernel_main

.halt:
    hlt
    jmp .halt

interrupt_init:
    SET_IDT 0, isr_stub_0
    SET_IDT 1, isr_stub_1
    SET_IDT 2, isr_stub_2
    SET_IDT 3, isr_stub_3
    SET_IDT 4, isr_stub_4
    SET_IDT 5, isr_stub_5
    SET_IDT 6, isr_stub_6
    SET_IDT 7, isr_stub_7
    SET_IDT 8, isr_stub_8
    SET_IDT 9, isr_stub_9
    SET_IDT 10, isr_stub_10
    SET_IDT 11, isr_stub_11
    SET_IDT 12, isr_stub_12
    SET_IDT 13, isr_stub_13
    SET_IDT 14, isr_stub_14
    SET_IDT 15, isr_stub_15
    SET_IDT 16, isr_stub_16
    SET_IDT 17, isr_stub_17
    SET_IDT 18, isr_stub_18
    SET_IDT 19, isr_stub_19
    SET_IDT 20, isr_stub_20
    SET_IDT 21, isr_stub_21
    SET_IDT 22, isr_stub_22
    SET_IDT 23, isr_stub_23
    SET_IDT 24, isr_stub_24
    SET_IDT 25, isr_stub_25
    SET_IDT 26, isr_stub_26
    SET_IDT 27, isr_stub_27
    SET_IDT 28, isr_stub_28
    SET_IDT 29, isr_stub_29
    SET_IDT 30, isr_stub_30
    SET_IDT 31, isr_stub_31
    lidt [rel idt_descriptor]
    ret

isr_common:
    cli
    push rsp
    push rax
    push rcx
    push rdx
    push rbx
    push rbp
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov rdi, rsp
    and rsp, -16
    call interrupt_handle

.fault_halt:
    hlt
    jmp .fault_halt

ISR_NOERR 0
ISR_NOERR 1
ISR_NOERR 2
ISR_NOERR 3
ISR_NOERR 4
ISR_NOERR 5
ISR_NOERR 6
ISR_NOERR 7
ISR_ERR   8
ISR_NOERR 9
ISR_ERR   10
ISR_ERR   11
ISR_ERR   12
ISR_ERR   13
ISR_ERR   14
ISR_NOERR 15
ISR_NOERR 16
ISR_ERR   17
ISR_NOERR 18
ISR_NOERR 19
ISR_NOERR 20
ISR_ERR   21
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28
ISR_ERR   29
ISR_ERR   30
ISR_NOERR 31

section .data
align 16
idtdescr_limit equ (32 * 16) - 1
idt_descriptor:
    dw idtdescr_limit
    dq idt_table

section .bss
align 16
idt_table:
    resb 32 * 16

align 16
stack_bottom:
    resb 16384
stack_top:
