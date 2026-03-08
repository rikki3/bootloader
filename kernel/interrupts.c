#include <stdint.h>
#include "platform.h"

typedef struct InterruptFrame {
    uint64_t r15;
    uint64_t r14;
    uint64_t r13;
    uint64_t r12;
    uint64_t r11;
    uint64_t r10;
    uint64_t r9;
    uint64_t r8;
    uint64_t rdi;
    uint64_t rsi;
    uint64_t rbp;
    uint64_t rbx;
    uint64_t rdx;
    uint64_t rcx;
    uint64_t rax;
    uint64_t fault_stack;
    uint64_t vector;
    uint64_t error;
    uint64_t rip;
    uint64_t cs;
    uint64_t rflags;
} InterruptFrame;

static const char* interrupt_name(uint64_t vector) {
    switch (vector) {
    case 0: return "divide error";
    case 1: return "debug";
    case 2: return "nmi";
    case 3: return "breakpoint";
    case 4: return "overflow";
    case 5: return "bound range";
    case 6: return "invalid opcode";
    case 7: return "device not available";
    case 8: return "double fault";
    case 10: return "invalid tss";
    case 11: return "segment not present";
    case 12: return "stack fault";
    case 13: return "general protection";
    case 14: return "page fault";
    case 16: return "x87 floating point";
    case 17: return "alignment check";
    case 18: return "machine check";
    case 19: return "simd floating point";
    case 21: return "control protection";
    case 29: return "vmm communication";
    case 30: return "security";
    default: return "processor exception";
    }
}

void interrupt_handle(const InterruptFrame* frame) {
    uint64_t cr2 = 0;
    const uint64_t* fault_rsp = (const uint64_t*) (uintptr_t) (frame->fault_stack + 40);

    if (frame->vector == 14) {
        __asm__ volatile("mov %%cr2, %0" : "=r"(cr2));
    }

    serial_write("\r\nfault: ");
    serial_write(interrupt_name(frame->vector));
    serial_write("\r\n");
    serial_printf("fault: vector 0x%llX error 0x%llX rip 0x%llX cs 0x%llX rflags 0x%llX\r\n",
                  (unsigned long long) frame->vector,
                  (unsigned long long) frame->error,
                  (unsigned long long) frame->rip,
                  (unsigned long long) frame->cs,
                  (unsigned long long) frame->rflags);
    serial_printf("fault: rax 0x%llX rbx 0x%llX rcx 0x%llX rdx 0x%llX\r\n",
                  (unsigned long long) frame->rax,
                  (unsigned long long) frame->rbx,
                  (unsigned long long) frame->rcx,
                  (unsigned long long) frame->rdx);
    serial_printf("fault: rsi 0x%llX rdi 0x%llX rbp 0x%llX\r\n",
                  (unsigned long long) frame->rsi,
                  (unsigned long long) frame->rdi,
                  (unsigned long long) frame->rbp);
    serial_printf("fault: caller_rip 0x%llX caller_rbp 0x%llX\r\n",
                  (unsigned long long) *(const uint64_t*) (uintptr_t) (frame->rbp + 8),
                  (unsigned long long) *(const uint64_t*) (uintptr_t) frame->rbp);
    serial_printf("fault: rsp 0x%llX [0]=0x%llX [1]=0x%llX [2]=0x%llX [3]=0x%llX\r\n",
                  (unsigned long long) fault_rsp,
                  (unsigned long long) fault_rsp[0],
                  (unsigned long long) fault_rsp[1],
                  (unsigned long long) fault_rsp[2],
                  (unsigned long long) fault_rsp[3]);
    if (frame->vector == 14) {
        serial_printf("fault: cr2 0x%llX\r\n", (unsigned long long) cr2);
    }
    halt_forever();
}
