#include <stddef.h>
#include <stdint.h>
#include "platform.h"

static volatile uint8_t* framebuffer;
static size_t framebuffer_size;

void vga_init(const BootInfo* info) {
    framebuffer = (volatile uint8_t*) (uintptr_t) info->framebuffer_base;
    framebuffer_size = (size_t) info->framebuffer_pitch * (size_t) info->framebuffer_height;
}

void vga_blit(const uint8_t* pixels, size_t size) {
    size_t i;
    if (framebuffer == 0) {
        return;
    }
    if (size > framebuffer_size) {
        size = framebuffer_size;
    }
    for (i = 0; i < size; ++i) {
        framebuffer[i] = pixels[i];
    }
}

void vga_set_palette_entry(uint8_t index, uint8_t r, uint8_t g, uint8_t b) {
    outb(0x3C8, index);
    outb(0x3C9, (uint8_t) (r >> 2));
    outb(0x3C9, (uint8_t) (g >> 2));
    outb(0x3C9, (uint8_t) (b >> 2));
}
