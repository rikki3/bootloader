#include <stdint.h>
#include "bootinfo.h"
#include "doom_wad.h"
#include "platform.h"
#include "doomgeneric.h"

extern uint8_t __kernel_end;

static void validate_boot_info(const BootInfo* info) {
    if (info == 0) {
        platform_panic("kernel: missing boot info");
    }
    if (info->magic != BOOTINFO_MAGIC) {
        platform_panic("kernel: bad boot info magic 0x%08X", info->magic);
    }
    if (info->version != BOOTINFO_VERSION) {
        platform_panic("kernel: unsupported boot info version 0x%08X", info->version);
    }
    if (info->framebuffer_base == 0 || info->framebuffer_bpp != 8
     || info->framebuffer_width != 320 || info->framebuffer_height != 200) {
        platform_panic("kernel: framebuffer setup invalid");
    }
    if (info->wad_base == 0 || info->wad_size == 0) {
        platform_panic("kernel: DOOM2.WAD was not preloaded");
    }
}

void kernel_main(const BootInfo* info) {
    static char arg0[] = "doom";
    static char arg1[] = "-iwad";
    static char arg2[] = "doom2.wad";
    static char* argv[] = { arg0, arg1, arg2, 0 };

    serial_init();
    validate_boot_info(info);
    platform_set_boot_info(info);

    serial_write("kernel: entered 64-bit long mode\r\n");
    serial_printf("kernel: boot info version 0x%08X\r\n", info->version);
    serial_printf("kernel: framebuffer 0x%llX %ux%u %u bpp\r\n",
                  (unsigned long long) info->framebuffer_base,
                  info->framebuffer_width,
                  info->framebuffer_height,
                  info->framebuffer_bpp);
    serial_printf("kernel: wad 0x%llX size 0x%llX\r\n",
                  (unsigned long long) info->wad_base,
                  (unsigned long long) info->wad_size);

    timer_init();
    vga_init(info);
    heap_init(info, (uintptr_t) &__kernel_end);
    keyboard_init();
    doom_wad_init(info->wad_base, info->wad_size);

    serial_printf("kernel: starting Doom\r\n");
    doomgeneric_Create(3, argv);

    for (;;) {
        doomgeneric_Tick();
    }
}
