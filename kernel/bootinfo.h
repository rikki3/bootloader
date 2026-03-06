#ifndef BOOTINFO_H
#define BOOTINFO_H

#include <stdint.h>

#define BOOTINFO_MAGIC 0x31544942u
#define BOOTINFO_VERSION 1u

typedef struct __attribute__((packed)) MemoryMapEntry {
    uint64_t base;
    uint64_t length;
    uint32_t type;
    uint32_t acpi;
} MemoryMapEntry;

typedef struct __attribute__((packed)) BootInfo {
    uint32_t magic;
    uint32_t version;
    uint32_t mmap_entry_size;
    uint32_t mmap_entry_count;
    uint64_t mmap_ptr;
    uint64_t framebuffer_base;
    uint32_t framebuffer_width;
    uint32_t framebuffer_height;
    uint32_t framebuffer_pitch;
    uint32_t framebuffer_bpp;
    uint32_t boot_drive;
    uint32_t reserved0;
    uint64_t boot_partition_lba;
    uint64_t kernel_entry;
    uint64_t kernel_load_base;
    uint64_t kernel_file_size;
    uint64_t acpi_rsdp;
} BootInfo;

#endif
