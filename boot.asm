[BITS 16]
[ORG 0x7C00]

%define STAGE2_LOAD_OFFSET 0x8000
%define STAGE2_SECTORS     128
%define FAT32_LBA_START    2048
%define IMAGE_SECTORS      131072
%define PARTITION_SECTORS  (IMAGE_SECTORS - FAT32_LBA_START)

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl
    call enable_a20

    mov si, msg_loading
    call print_string

    mov word [disk_packet.sector_count], STAGE2_SECTORS
    mov word [disk_packet.buffer_offset], STAGE2_LOAD_OFFSET
    mov word [disk_packet.buffer_segment], 0
    mov dword [disk_packet.lba_low], 1
    mov dword [disk_packet.lba_high], 0

    mov si, disk_packet
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    mov dl, [boot_drive]
    jmp 0x0000:STAGE2_LOAD_OFFSET

disk_error:
    mov si, msg_disk_error
    call print_string
.hang:
    cli
    hlt
    jmp .hang

enable_a20:
    in al, 0x92
    or al, 0x02
    out 0x92, al
    ret

print_string:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp print_string
.done:
    ret

boot_drive db 0
msg_loading db 'stage1: loading stage2', 13, 10, 0
msg_disk_error db 'stage1: disk read failed', 13, 10, 0

disk_packet:
    db 0x10
    db 0
.sector_count dw 0
.buffer_offset dw 0
.buffer_segment dw 0
.lba_low dd 0
.lba_high dd 0

times 446 - ($ - $$) db 0

db 0x80, 0x00, 0x02, 0x00, 0x0C, 0xFF, 0xFF, 0xFF
dd FAT32_LBA_START
dd PARTITION_SECTORS
times 16 * 3 db 0

dw 0xAA55
