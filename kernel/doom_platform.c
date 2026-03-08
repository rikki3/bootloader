#include <stdint.h>
#include "doomgeneric.h"
#include "i_video.h"
#include "platform.h"

void DG_Init(void) {
}

void DG_DrawFrame(void) {
    int i;

#ifdef CMAP256
    if (palette_changed) {
        for (i = 0; i < 256; ++i) {
            vga_set_palette_entry((uint8_t) i, colors[i].r, colors[i].g, colors[i].b);
        }
        palette_changed = false;
    }
#endif

    vga_blit((const uint8_t*) DG_ScreenBuffer, 320u * 200u);
}

void DG_SleepMs(uint32_t ms) {
    timer_sleep_ms(ms);
}

uint32_t DG_GetTicksMs(void) {
    return timer_ticks_ms();
}

int DG_GetKey(int* pressed, unsigned char* key) {
    return keyboard_pop_event(pressed, key);
}

void DG_SetWindowTitle(const char* title) {
    serial_printf("doom: %s\r\n", title);
}
