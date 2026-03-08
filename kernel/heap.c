#include <stddef.h>
#include <stdint.h>
#include "platform.h"

typedef struct HeapBlock {
    size_t size;
    int free;
    struct HeapBlock* next;
} HeapBlock;

static HeapBlock* heap_head;

static uintptr_t align_up(uintptr_t value, uintptr_t alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

static void maybe_use_range(uintptr_t start, uintptr_t end,
                            uintptr_t* best_start, uintptr_t* best_size) {
    uintptr_t size;

    start = align_up(start, 16);
    end &= ~(uintptr_t) 15;
    if (end <= start) {
        return;
    }

    size = end - start;
    if (size > *best_size) {
        *best_start = start;
        *best_size = size;
    }
}

static void consider_excluding(uintptr_t range_start, uintptr_t range_end,
                               uintptr_t exclude_start, uintptr_t exclude_end,
                               uintptr_t* best_start, uintptr_t* best_size) {
    if (exclude_end <= range_start || exclude_start >= range_end) {
        maybe_use_range(range_start, range_end, best_start, best_size);
        return;
    }

    maybe_use_range(range_start, exclude_start, best_start, best_size);
    maybe_use_range(exclude_end, range_end, best_start, best_size);
}

static void consider_excluding_pair(uintptr_t range_start, uintptr_t range_end,
                                    uintptr_t first_start, uintptr_t first_end,
                                    uintptr_t second_start, uintptr_t second_end,
                                    uintptr_t* best_start, uintptr_t* best_size) {
    uintptr_t exclude_start[2];
    uintptr_t exclude_end[2];
    size_t exclude_count = 0;

    if (!(first_end <= range_start || first_start >= range_end)) {
        if (first_start < range_start) {
            first_start = range_start;
        }
        if (first_end > range_end) {
            first_end = range_end;
        }
        exclude_start[exclude_count] = first_start;
        exclude_end[exclude_count] = first_end;
        ++exclude_count;
    }

    if (!(second_end <= range_start || second_start >= range_end)) {
        if (second_start < range_start) {
            second_start = range_start;
        }
        if (second_end > range_end) {
            second_end = range_end;
        }
        exclude_start[exclude_count] = second_start;
        exclude_end[exclude_count] = second_end;
        ++exclude_count;
    }

    if (exclude_count == 0) {
        maybe_use_range(range_start, range_end, best_start, best_size);
        return;
    }

    if (exclude_count == 2 && exclude_start[1] < exclude_start[0]) {
        uintptr_t start = exclude_start[0];
        uintptr_t end = exclude_end[0];
        exclude_start[0] = exclude_start[1];
        exclude_end[0] = exclude_end[1];
        exclude_start[1] = start;
        exclude_end[1] = end;
    }

    if (exclude_count == 2 && exclude_start[1] <= exclude_end[0]) {
        if (exclude_end[1] > exclude_end[0]) {
            exclude_end[0] = exclude_end[1];
        }
        exclude_count = 1;
    }

    maybe_use_range(range_start, exclude_start[0], best_start, best_size);

    if (exclude_count == 2) {
        maybe_use_range(exclude_end[0], exclude_start[1], best_start, best_size);
        maybe_use_range(exclude_end[1], range_end, best_start, best_size);
        return;
    }

    maybe_use_range(exclude_end[0], range_end, best_start, best_size);
}

static void select_heap_region(const BootInfo* info,
                               uintptr_t kernel_start,
                               uintptr_t kernel_end,
                               uintptr_t* best_start,
                               uintptr_t* best_size) {
    uintptr_t wad_start = (uintptr_t) info->wad_base;
    uintptr_t wad_end = wad_start + (uintptr_t) info->wad_size;
    uint32_t i;
    const MemoryMapEntry* mmap = (const MemoryMapEntry*) (uintptr_t) info->mmap_ptr;

    *best_start = 0;
    *best_size = 0;

    for (i = 0; i < info->mmap_entry_count; ++i) {
        uintptr_t range_start;
        uintptr_t range_end;

        if (mmap[i].type != 1) {
            continue;
        }

        range_start = (uintptr_t) mmap[i].base;
        range_end = range_start + (uintptr_t) mmap[i].length;

        if (range_end <= 0x00100000 || range_start >= 0x08000000) {
            continue;
        }

        if (range_start < 0x00100000) {
            range_start = 0x00100000;
        }
        if (range_end > 0x08000000) {
            range_end = 0x08000000;
        }

        consider_excluding_pair(range_start, range_end,
                                kernel_start, kernel_end,
                                wad_start, wad_end,
                                best_start, best_size);
    }
}

void heap_init(const BootInfo* info, uintptr_t kernel_end) {
    uintptr_t best_start;
    uintptr_t best_size;
    uintptr_t kernel_start = (uintptr_t) info->kernel_load_base;
    kernel_end = align_up(kernel_end, 0x1000);

    select_heap_region(info, kernel_start, kernel_end, &best_start, &best_size);

    if (best_start == 0 || best_size <= sizeof(HeapBlock) + 4096) {
        platform_panic("heap: no usable memory region below 128 MiB");
    }

    heap_head = (HeapBlock*) best_start;
    heap_head->size = best_size - sizeof(HeapBlock);
    heap_head->free = 1;
    heap_head->next = 0;

    serial_printf("kernel: heap 0x%llX size 0x%llX\r\n",
                  (unsigned long long) best_start,
                  (unsigned long long) best_size);
}

static size_t block_size(size_t size) {
    if (size < 16) {
        size = 16;
    }
    return (size + 15u) & ~15u;
}

static void split_block(HeapBlock* block, size_t size) {
    HeapBlock* next;

    if (block->size <= size + sizeof(HeapBlock) + 16) {
        return;
    }

    next = (HeapBlock*) ((uint8_t*) (block + 1) + size);
    next->size = block->size - size - sizeof(HeapBlock);
    next->free = 1;
    next->next = block->next;

    block->size = size;
    block->next = next;
}

static void coalesce(void) {
    HeapBlock* block = heap_head;

    while (block != 0 && block->next != 0) {
        uint8_t* block_end = (uint8_t*) (block + 1) + block->size;
        if (block->free && block->next->free && block_end == (uint8_t*) block->next) {
            block->size += sizeof(HeapBlock) + block->next->size;
            block->next = block->next->next;
            continue;
        }
        block = block->next;
    }
}

void* heap_malloc(size_t size) {
    HeapBlock* block;

    if (size == 0) {
        size = 1;
    }

    size = block_size(size);
    for (block = heap_head; block != 0; block = block->next) {
        if (block->free && block->size >= size) {
            split_block(block, size);
            block->free = 0;
            return block + 1;
        }
    }

    return 0;
}

void* heap_calloc(size_t count, size_t size) {
    size_t total = count * size;
    void* ptr = heap_malloc(total);
    if (ptr != 0) {
        uint8_t* bytes = (uint8_t*) ptr;
        size_t i;
        for (i = 0; i < total; ++i) {
            bytes[i] = 0;
        }
    }
    return ptr;
}

void heap_free(void* ptr) {
    HeapBlock* block;

    if (ptr == 0) {
        return;
    }

    block = ((HeapBlock*) ptr) - 1;
    block->free = 1;
    coalesce();
}

void* heap_realloc(void* ptr, size_t size) {
    HeapBlock* block;
    void* fresh;
    size_t copy_size;
    size_t i;

    if (ptr == 0) {
        return heap_malloc(size);
    }
    if (size == 0) {
        heap_free(ptr);
        return 0;
    }

    block = ((HeapBlock*) ptr) - 1;
    if (block->size >= size) {
        split_block(block, block_size(size));
        return ptr;
    }

    fresh = heap_malloc(size);
    if (fresh == 0) {
        return 0;
    }

    copy_size = block->size;
    if (copy_size > size) {
        copy_size = size;
    }

    for (i = 0; i < copy_size; ++i) {
        ((uint8_t*) fresh)[i] = ((const uint8_t*) ptr)[i];
    }

    heap_free(ptr);
    return fresh;
}
