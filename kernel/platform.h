#ifndef KERNEL_PLATFORM_H
#define KERNEL_PLATFORM_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include "bootinfo.h"

extern const BootInfo* g_boot_info;

static inline void outb(uint16_t port, uint8_t value) {
    __asm__ volatile("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t value;
    __asm__ volatile("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

static inline uint16_t inw(uint16_t port) {
    uint16_t value;
    __asm__ volatile("inw %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

static inline uint64_t read_tsc(void) {
    uint32_t lo;
    uint32_t hi;
    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    return ((uint64_t) hi << 32) | lo;
}

static inline void cpuid(uint32_t leaf, uint32_t subleaf,
                         uint32_t* eax, uint32_t* ebx,
                         uint32_t* ecx, uint32_t* edx) {
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
    __asm__ volatile("cpuid"
                     : "=a"(a), "=b"(b), "=c"(c), "=d"(d)
                     : "a"(leaf), "c"(subleaf));
    if (eax != 0) {
        *eax = a;
    }
    if (ebx != 0) {
        *ebx = b;
    }
    if (ecx != 0) {
        *ecx = c;
    }
    if (edx != 0) {
        *edx = d;
    }
}

void platform_set_boot_info(const BootInfo* info);
void serial_init(void);
void serial_putc(char c);
void serial_write(const char* text);
void serial_printf(const char* fmt, ...);
void serial_vprintf(const char* fmt, va_list args);

void halt_forever(void) __attribute__((noreturn));
void platform_panic(const char* fmt, ...) __attribute__((noreturn));

void heap_init(const BootInfo* info, uintptr_t kernel_end);
void* heap_malloc(size_t size);
void* heap_calloc(size_t count, size_t size);
void* heap_realloc(void* ptr, size_t size);
void heap_free(void* ptr);

void timer_init(void);
uint32_t timer_ticks_ms(void);
void timer_sleep_ms(uint32_t ms);

void keyboard_init(void);
void keyboard_pump(void);
int keyboard_pop_event(int* pressed, unsigned char* key);

void vga_init(const BootInfo* info);
void vga_blit(const uint8_t* pixels, size_t size);
void vga_set_palette_entry(uint8_t index, uint8_t r, uint8_t g, uint8_t b);

#endif
