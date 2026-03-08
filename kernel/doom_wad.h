#ifndef KERNEL_DOOM_WAD_H
#define KERNEL_DOOM_WAD_H

#include <stddef.h>
#include <stdint.h>

void doom_wad_init(uint64_t base, uint64_t size);
int doom_wad_match_path(const char* path, const uint8_t** data, size_t* size);

#endif
