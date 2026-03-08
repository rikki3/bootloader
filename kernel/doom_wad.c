#include <stdlib.h>
#include <string.h>
#include "doom_wad.h"
#include "w_file.h"

extern wad_file_class_t stdc_wad_file;

typedef struct BootWadFile {
    wad_file_t wad;
    const uint8_t* data;
} BootWadFile;

static const uint8_t* doom_wad_data;
static size_t doom_wad_size;

static const char* path_basename(const char* path) {
    const char* base = path;
    while (*path != '\0') {
        if (*path == '/' || *path == '\\') {
            base = path + 1;
        }
        ++path;
    }
    return base;
}

void doom_wad_init(uint64_t base, uint64_t size) {
    doom_wad_data = (const uint8_t*) (uintptr_t) base;
    doom_wad_size = (size_t) size;
}

int doom_wad_match_path(const char* path, const uint8_t** data, size_t* size) {
    const char* base = path_basename(path);
    if (doom_wad_data == 0 || doom_wad_size == 0) {
        return 0;
    }
    if (strcasecmp(base, "doom2.wad") != 0) {
        return 0;
    }
    *data = doom_wad_data;
    *size = doom_wad_size;
    return 1;
}

static wad_file_t* boot_wad_open(char* path) {
    const uint8_t* data;
    size_t size;
    BootWadFile* file;

    if (!doom_wad_match_path(path, &data, &size)) {
        return 0;
    }

    file = malloc(sizeof(*file));
    if (file == 0) {
        return 0;
    }

    file->wad.file_class = &stdc_wad_file;
    file->wad.mapped = (byte*) data;
    file->wad.length = (unsigned int) size;
    file->data = data;
    return &file->wad;
}

static void boot_wad_close(wad_file_t* wad) {
    free(wad);
}

static size_t boot_wad_read(wad_file_t* wad, unsigned int offset, void* buffer, size_t buffer_len) {
    const BootWadFile* file = (const BootWadFile*) wad;
    size_t available = wad->length;

    if ((size_t) offset >= available) {
        return 0;
    }

    available -= offset;
    if (buffer_len > available) {
        buffer_len = available;
    }

    memcpy(buffer, file->data + offset, buffer_len);
    return buffer_len;
}

wad_file_class_t stdc_wad_file = {
    boot_wad_open,
    boot_wad_close,
    boot_wad_read,
};
