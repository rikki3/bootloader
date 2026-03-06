MSYS2_ROOT ?= /c/Users/RICKES~1/AppData/Local/msys64

NASM   := $(MSYS2_ROOT)/usr/bin/nasm
CLANG  := $(MSYS2_ROOT)/ucrt64/bin/clang
LD     := $(MSYS2_ROOT)/ucrt64/bin/ld.lld
QEMU   := $(MSYS2_ROOT)/ucrt64/bin/qemu-system-x86_64
MFORMAT:= $(MSYS2_ROOT)/usr/bin/mkfs.fat
MMD    := $(MSYS2_ROOT)/ucrt64/bin/mmd
MCOPY  := $(MSYS2_ROOT)/ucrt64/bin/mcopy

BUILD_DIR      := build
IMAGE          := $(BUILD_DIR)/disk.img
STAGE1_BIN     := $(BUILD_DIR)/stage1.bin
STAGE2_BIN     := $(BUILD_DIR)/stage2.bin
KERNEL_ELF     := $(BUILD_DIR)/kernel.elf
KERNEL_ENTRY_O := $(BUILD_DIR)/kernel_entry.o
KERNEL_MAIN_O  := $(BUILD_DIR)/kernel_main.o

IMAGE_SECTORS      := 131072
PARTITION_LBA      := 2048
PARTITION_OFFSET   := 1048576
STAGE2_SECTORS     := 128

CFLAGS := --target=x86_64-elf -ffreestanding -fno-pic -fno-stack-protector -mno-red-zone -Wall -Wextra -O2 -Ikernel
LDFLAGS := -m elf_x86_64 -T kernel/link.ld -nostdlib

.PHONY: all clean run run-headless stage1 image

all: $(IMAGE)

stage1: $(STAGE1_BIN)

image: $(IMAGE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(STAGE1_BIN): boot.asm | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $<

$(STAGE2_BIN): boot/stage2.asm | $(BUILD_DIR)
	$(NASM) -f bin -o $@ $<

$(KERNEL_ENTRY_O): kernel/entry.asm | $(BUILD_DIR)
	$(NASM) -f elf64 -o $@ $<

$(KERNEL_MAIN_O): kernel/main.c kernel/bootinfo.h | $(BUILD_DIR)
	$(CLANG) $(CFLAGS) -c -o $@ $<

$(KERNEL_ELF): $(KERNEL_ENTRY_O) $(KERNEL_MAIN_O) kernel/link.ld
	$(LD) $(LDFLAGS) -o $@ $(KERNEL_ENTRY_O) $(KERNEL_MAIN_O)

$(IMAGE): $(STAGE1_BIN) $(STAGE2_BIN) $(KERNEL_ELF) | $(BUILD_DIR)
	dd if=/dev/zero of=$@ bs=512 count=$(IMAGE_SECTORS)
	dd if=$(STAGE1_BIN) of=$@ conv=notrunc
	dd if=$(STAGE2_BIN) of=$@ bs=512 seek=1 conv=sync,notrunc
	$(MFORMAT) -F 32 -s 1 --offset=$(PARTITION_LBA) $@
	printf 'drive z: file="%s" offset=%s\n' "$$(cygpath -m "$(abspath $(IMAGE))")" "$(PARTITION_OFFSET)" > $(BUILD_DIR)/mtoolsrc
	MTOOLSRC=$(BUILD_DIR)/mtoolsrc $(MMD) z:/BOOT
	MTOOLSRC=$(BUILD_DIR)/mtoolsrc $(MCOPY) $(KERNEL_ELF) z:/BOOT/KERNEL.ELF

run: $(IMAGE)
	$(QEMU) -drive format=raw,file=$(abspath $(IMAGE))

run-headless: $(IMAGE)
	$(QEMU) -drive format=raw,file=$(abspath $(IMAGE)) -display none -serial stdio -monitor none

clean:
	rm -rf $(BUILD_DIR)
