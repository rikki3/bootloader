#include <stdio.h>
#include "platform.h"

const BootInfo* g_boot_info;
int format_vbuffer(char* buffer, size_t size, const char* format, va_list* args);

void platform_set_boot_info(const BootInfo* info) {
    g_boot_info = info;
}

void serial_init(void) {
    outb(0x3F8 + 1, 0x00);
    outb(0x3F8 + 3, 0x80);
    outb(0x3F8 + 0, 0x03);
    outb(0x3F8 + 1, 0x00);
    outb(0x3F8 + 3, 0x03);
    outb(0x3F8 + 2, 0xC7);
    outb(0x3F8 + 4, 0x0B);
}

void serial_putc(char c) {
    while ((inb(0x3F8 + 5) & 0x20) == 0) {
    }
    outb(0x3F8, (uint8_t) c);
}

void serial_write(const char* text) {
    while (*text != '\0') {
        if (*text == '\n') {
            serial_putc('\r');
        }
        serial_putc(*text++);
    }
}

void serial_vprintf(const char* fmt, va_list args) {
    char buffer[1024];
    va_list copy;
    va_copy(copy, args);
    format_vbuffer(buffer, sizeof(buffer), fmt, &copy);
    va_end(copy);
    serial_write(buffer);
}

void serial_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    serial_vprintf(fmt, args);
    va_end(args);
}

void halt_forever(void) {
    for (;;) {
        __asm__ volatile("hlt");
    }
}

void platform_panic(const char* fmt, ...) {
    va_list args;
    serial_write("panic: ");
    va_start(args, fmt);
    serial_vprintf(fmt, args);
    va_end(args);
    serial_write("\r\n");
    halt_forever();
}
