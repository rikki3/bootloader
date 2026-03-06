#include <stdint.h>
#include "bootinfo.h"

static volatile uint16_t* const VGA = (volatile uint16_t*)0xB8000;
static uint16_t cursor;

static void serial_init(void) {
    const uint16_t com1 = 0x3F8;
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)0x00), "Nd"((uint16_t)(com1 + 1)));
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)0x80), "Nd"((uint16_t)(com1 + 3)));
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)0x03), "Nd"((uint16_t)(com1 + 0)));
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)0x00), "Nd"((uint16_t)(com1 + 1)));
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)0x03), "Nd"((uint16_t)(com1 + 3)));
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)0xC7), "Nd"((uint16_t)(com1 + 2)));
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)0x0B), "Nd"((uint16_t)(com1 + 4)));
}

static void serial_putc(char c) {
    const uint16_t status = 0x3F8 + 5;
    const uint16_t data = 0x3F8;
    uint8_t ready = 0;
    while ((ready & 0x20) == 0) {
        __asm__ volatile("inb %1, %0" : "=a"(ready) : "Nd"(status));
    }
    __asm__ volatile("outb %0, %1" : : "a"((uint8_t)c), "Nd"(data));
}

static void clear_screen(void) {
    for (uint16_t i = 0; i < 80 * 25; ++i) {
        VGA[i] = 0x0720;
    }
    cursor = 0;
}

static void putc(char c) {
    if (c == '\r') {
        cursor -= (cursor % 80);
        serial_putc(c);
        return;
    }
    if (c == '\n') {
        cursor += (uint16_t)(80 - (cursor % 80));
        serial_putc(c);
        return;
    }

    if (cursor >= 80 * 25) {
        cursor = 0;
    }

    VGA[cursor++] = (uint16_t)(0x0700 | (uint8_t)c);
    serial_putc(c);
}

static void puts(const char* text) {
    while (*text) {
        putc(*text++);
    }
}

static void hex32(uint32_t value) {
    static const char digits[] = "0123456789ABCDEF";
    for (int shift = 28; shift >= 0; shift -= 4) {
        putc(digits[(value >> shift) & 0xF]);
    }
}

static void hex64(uint64_t value) {
    hex32((uint32_t)(value >> 32));
    hex32((uint32_t)value);
}

void kernel_main(const BootInfo* info) {
    serial_init();
    clear_screen();

    puts("kernel: entered 64-bit long mode\r\n");

    if (!info || info->magic != BOOTINFO_MAGIC) {
        puts("kernel: invalid boot info\r\n");
        return;
    }

    puts("kernel: boot info version 0x");
    hex32(info->version);
    puts("\r\n");

    puts("kernel: boot drive 0x");
    hex32(info->boot_drive);
    puts("\r\n");

    puts("kernel: partition lba 0x");
    hex64(info->boot_partition_lba);
    puts("\r\n");

    puts("kernel: mmap entries 0x");
    hex32(info->mmap_entry_count);
    puts("\r\n");

    puts("kernel: kernel entry 0x");
    hex64(info->kernel_entry);
    puts("\r\n");

    puts("kernel: kernel load base 0x");
    hex64(info->kernel_load_base);
    puts("\r\n");

    puts("kernel: acpi rsdp 0x");
    hex64(info->acpi_rsdp);
    puts("\r\n");
}
