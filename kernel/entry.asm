[BITS 64]

section .text
global kernel_entry
extern kernel_main

kernel_entry:
    cli
    cld
    mov rsp, stack_top
    mov rbp, rsp
    call kernel_main

.halt:
    hlt
    jmp .halt

section .bss
align 16
stack_bottom:
    resb 16384
stack_top:
