#include <stdint.h>
#include "doomkeys.h"
#include "platform.h"

typedef struct KeyEvent {
    int pressed;
    unsigned char key;
} KeyEvent;

#define KEY_QUEUE_SIZE 64

static KeyEvent queue[KEY_QUEUE_SIZE];
static uint32_t queue_head;
static uint32_t queue_tail;
static int extended_prefix;

static void push_event(int pressed, unsigned char key) {
    uint32_t next = (queue_tail + 1u) % KEY_QUEUE_SIZE;
    if (next == queue_head || key == 0) {
        return;
    }
    queue[queue_tail].pressed = pressed;
    queue[queue_tail].key = key;
    queue_tail = next;
}

static unsigned char translate_scancode(uint8_t scancode, int extended) {
    switch (scancode) {
    case 0x01: return KEY_ESCAPE;
    case 0x02: return '1';
    case 0x03: return '2';
    case 0x04: return '3';
    case 0x05: return '4';
    case 0x06: return '5';
    case 0x07: return '6';
    case 0x08: return '7';
    case 0x09: return '8';
    case 0x0A: return '9';
    case 0x0B: return '0';
    case 0x0C: return '-';
    case 0x0D: return '=';
    case 0x0E: return KEY_BACKSPACE;
    case 0x0F: return KEY_TAB;
    case 0x10: return 'q';
    case 0x11: return 'w';
    case 0x12: return 'e';
    case 0x13: return 'r';
    case 0x14: return 't';
    case 0x15: return 'y';
    case 0x16: return 'u';
    case 0x17: return 'i';
    case 0x18: return 'o';
    case 0x19: return 'p';
    case 0x1A: return '[';
    case 0x1B: return ']';
    case 0x1C: return KEY_ENTER;
    case 0x1D: return KEY_FIRE;
    case 0x1E: return 'a';
    case 0x1F: return 's';
    case 0x20: return 'd';
    case 0x21: return 'f';
    case 0x22: return 'g';
    case 0x23: return 'h';
    case 0x24: return 'j';
    case 0x25: return 'k';
    case 0x26: return 'l';
    case 0x27: return ';';
    case 0x28: return '\'';
    case 0x29: return '`';
    case 0x2A: return KEY_RSHIFT;
    case 0x2B: return '\\';
    case 0x2C: return 'z';
    case 0x2D: return 'x';
    case 0x2E: return 'c';
    case 0x2F: return 'v';
    case 0x30: return 'b';
    case 0x31: return 'n';
    case 0x32: return 'm';
    case 0x33: return KEY_STRAFE_L;
    case 0x34: return KEY_STRAFE_R;
    case 0x35: return '/';
    case 0x36: return KEY_RSHIFT;
    case 0x38: return KEY_LALT;
    case 0x39: return KEY_USE;
    case 0x3B: return KEY_F1;
    case 0x3C: return KEY_F2;
    case 0x3D: return KEY_F3;
    case 0x3E: return KEY_F4;
    case 0x3F: return KEY_F5;
    case 0x40: return KEY_F6;
    case 0x41: return KEY_F7;
    case 0x42: return KEY_F8;
    case 0x43: return KEY_F9;
    case 0x44: return KEY_F10;
    case 0x57: return KEY_F11;
    case 0x58: return KEY_F12;
    default:
        break;
    }

    if (extended) {
        switch (scancode) {
        case 0x1C: return KEY_ENTER;
        case 0x1D: return KEY_FIRE;
        case 0x38: return KEY_RALT;
        case 0x47: return KEY_HOME;
        case 0x48: return KEY_UPARROW;
        case 0x49: return KEY_PGUP;
        case 0x4B: return KEY_LEFTARROW;
        case 0x4D: return KEY_RIGHTARROW;
        case 0x4F: return KEY_END;
        case 0x50: return KEY_DOWNARROW;
        case 0x51: return KEY_PGDN;
        case 0x52: return KEY_INS;
        case 0x53: return KEY_DEL;
        default:
            return 0;
        }
    }

    switch (scancode) {
    case 0x47: return KEY_HOME;
    case 0x48: return KEY_UPARROW;
    case 0x49: return KEY_PGUP;
    case 0x4B: return KEY_LEFTARROW;
    case 0x4D: return KEY_RIGHTARROW;
    case 0x4F: return KEY_END;
    case 0x50: return KEY_DOWNARROW;
    case 0x51: return KEY_PGDN;
    case 0x52: return KEY_INS;
    case 0x53: return KEY_DEL;
    default:
        return 0;
    }
}

void keyboard_init(void) {
    queue_head = 0;
    queue_tail = 0;
    extended_prefix = 0;
}

void keyboard_pump(void) {
    while ((inb(0x64) & 0x01) != 0) {
        uint8_t scancode = inb(0x60);
        int pressed;
        unsigned char key;

        if (scancode == 0xE0) {
            extended_prefix = 1;
            continue;
        }
        if (scancode == 0xE1) {
            extended_prefix = 0;
            continue;
        }

        pressed = (scancode & 0x80) == 0;
        key = translate_scancode((uint8_t) (scancode & 0x7F), extended_prefix);
        extended_prefix = 0;
        push_event(pressed, key);
    }
}

int keyboard_pop_event(int* pressed, unsigned char* key) {
    keyboard_pump();
    if (queue_head == queue_tail) {
        return 0;
    }

    *pressed = queue[queue_head].pressed;
    *key = queue[queue_head].key;
    queue_head = (queue_head + 1u) % KEY_QUEUE_SIZE;
    return 1;
}
