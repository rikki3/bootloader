#include <stdint.h>
#include "platform.h"

#define PIT_FREQUENCY 1193182ULL

static uint64_t tsc_hz;
static uint64_t tsc_start;

static uint64_t calibrate_tsc_with_pit(void) {
    const uint16_t count = 0xFFFF;
    uint8_t port61 = inb(0x61);
    uint64_t start;
    uint64_t end;

    outb(0x61, (uint8_t) ((port61 & ~0x03u) | 0x01u));
    outb(0x43, 0xB0);
    outb(0x42, (uint8_t) (count & 0xFF));
    outb(0x42, (uint8_t) (count >> 8));

    start = read_tsc();
    while ((inb(0x61) & 0x20) == 0) {
    }
    end = read_tsc();

    outb(0x61, port61);
    if (end <= start) {
        return 0;
    }

    return ((end - start) * PIT_FREQUENCY) / count;
}

static uint64_t detect_tsc_hz(void) {
    uint32_t max_leaf;
    uint32_t eax;
    uint32_t ebx;
    uint32_t ecx;
    uint32_t edx;

    cpuid(0, 0, &max_leaf, &ebx, &ecx, &edx);

    if (max_leaf >= 0x15) {
        cpuid(0x15, 0, &eax, &ebx, &ecx, &edx);
        if (eax != 0 && ebx != 0 && ecx != 0) {
            return ((uint64_t) ecx * (uint64_t) ebx) / (uint64_t) eax;
        }
    }

    if (max_leaf >= 0x16) {
        cpuid(0x16, 0, &eax, &ebx, &ecx, &edx);
        if (eax != 0) {
            return (uint64_t) eax * 1000000ULL;
        }
    }

    return calibrate_tsc_with_pit();
}

void timer_init(void) {
    tsc_hz = detect_tsc_hz();
    if (tsc_hz == 0) {
        platform_panic("timer: could not determine TSC frequency");
    }

    tsc_start = read_tsc();
    serial_printf("kernel: tsc 0x%llX Hz\r\n", (unsigned long long) tsc_hz);
}

uint32_t timer_ticks_ms(void) {
    uint64_t delta = read_tsc() - tsc_start;
    return (uint32_t) ((delta * 1000ULL) / tsc_hz);
}

void timer_sleep_ms(uint32_t ms) {
    uint32_t start = timer_ticks_ms();
    while ((uint32_t) (timer_ticks_ms() - start) < ms) {
    }
}
