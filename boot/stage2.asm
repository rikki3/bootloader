[BITS 16]
[ORG 0x8000]

%define COM1                0x3F8
%define KERNEL_FILE_SEG     0x2000
%define KERNEL_FILE_OFFSET  0x0000
%define KERNEL_FILE_PHYS    0x20000
%define KERNEL_FILE_MAX_SIZE 0x00070000
%define KERNEL_LOAD_SEG     0x2100
%define KERNEL_LOAD_PHYS    0x00021000
%define KERNEL_LOAD_OFFSET  0x0000
%define PAGE_TABLE_PML4     0x1000
%define PAGE_TABLE_PDPT     0x2000
%define PAGE_TABLE_PD       0x3000
%define E820_ENTRY_SIZE     24
%define E820_MAX_ENTRIES    64
%define BOOTINFO_MAGIC      0x31544942
%define BOOTINFO_VERSION    1
%define BOOTINFO_SIZE       96
%define FAT32_EOC           0x0FFFFFF8
%define FAT32_PARTITION_LBA 2048
%define AUTOBOOT_TICKS      273

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, stage2_stack_top
    sti

    mov [boot_drive], dl
    call serial_init
    call init_boot_info
    call clear_screen

    mov si, banner
    call puts

    call collect_memory_map
    call detect_acpi_rsdp

    call autoboot_or_shell

shell_loop:
    mov si, prompt
    call puts
    call read_line
    cmp byte [command_buffer], 0
    je shell_loop

    mov si, command_buffer
    mov di, cmd_help
    call strings_equal
    jc .check_clear
    call cmd_show_help
    jmp shell_loop

.check_clear:
    mov si, command_buffer
    mov di, cmd_clear
    call strings_equal
    jc .check_info
    call clear_screen
    jmp shell_loop

.check_info:
    mov si, command_buffer
    mov di, cmd_info
    call strings_equal
    jc .check_dir
    call cmd_show_info
    jmp shell_loop

.check_dir:
    mov si, command_buffer
    mov di, cmd_dir
    call strings_equal
    jc .check_mmap
    call cmd_show_dir
    jmp shell_loop

.check_mmap:
    mov si, command_buffer
    mov di, cmd_mmap
    call strings_equal
    jc .check_gfx
    call cmd_show_mmap
    jmp shell_loop

.check_gfx:
    mov si, command_buffer
    mov di, cmd_gfx
    call strings_equal
    jc .check_boot
    call cmd_show_graphics
    jmp shell_loop

.check_boot:
    mov si, command_buffer
    mov di, cmd_boot
    call strings_equal
    jc .check_reboot
    call boot_kernel
    jmp shell_loop

.check_reboot:
    mov si, command_buffer
    mov di, cmd_reboot
    call strings_equal
    jc .unknown
    int 0x19
    jmp $

.unknown:
    mov si, msg_unknown
    call puts
    jmp shell_loop

autoboot_or_shell:
    mov si, msg_autoboot
    call puts

    mov bx, [0x046C]
.wait:
    mov ah, 0x01
    int 0x16
    jnz .enter_shell

    mov ax, [0x046C]
    sub ax, bx
    cmp ax, AUTOBOOT_TICKS
    jb .wait

    mov si, msg_autobooting
    call puts
    call boot_kernel
    ret

.enter_shell:
    xor ah, ah
    int 0x16
    mov si, msg_shell
    call puts
    ret

boot_kernel:
    mov si, msg_kernel_load
    call puts
    call load_kernel_from_fat32
    jc .fail
    mov si, msg_step_file_loaded
    call puts_serial_only

    call load_elf64
    jc .fail
    mov si, msg_step_elf_loaded
    call puts_serial_only

    mov si, msg_kernel_jump
    call puts
    cli
    call enter_long_mode
    jmp $

.fail:
    mov si, msg_kernel_fail
    call puts
    stc
    ret

load_kernel_from_fat32:
    call ensure_fat32_ready
    jc .fail
    mov si, msg_step_fat_ready
    call puts_serial_only

    mov eax, [root_cluster]
    mov si, name_boot_dir
    call fat32_find_entry
    jc .fail
    test byte [found_attr], 0x10
    jz .fail

    mov eax, [found_cluster]
    mov [current_directory_cluster], eax

    mov eax, [current_directory_cluster]
    mov si, name_kernel_file
    call fat32_find_entry
    jc .fail
    test byte [found_attr], 0x10
    jnz .fail
    mov si, msg_step_kernel_found
    call puts_serial_only

    mov eax, [found_size]
    cmp eax, KERNEL_FILE_MAX_SIZE
    ja .too_large
    mov [kernel_file_size], eax

    mov eax, [found_cluster]
    call fat32_load_file
    ret

.too_large:
    mov si, msg_kernel_too_large
    call puts
.fail:
    stc
    ret

ensure_fat32_ready:
    cmp byte [fat32_ready], 1
    je .ready

    call fat32_init
    jc .fail
    mov byte [fat32_ready], 1

.ready:
    clc
    ret

.fail:
    stc
    ret

clear_screen:
    mov ax, 0x0003
    int 0x10
    ret

cmd_show_help:
    mov si, help_text
    call puts
    ret

cmd_show_info:
    call ensure_fat32_ready
    mov si, msg_info_boot_drive
    call puts
    movzx eax, byte [boot_drive]
    call print_hex32
    call newline

    mov si, msg_info_partition
    call puts
    mov eax, [partition_lba]
    call print_hex32
    call newline

    mov si, msg_info_root_cluster
    call puts
    mov eax, [root_cluster]
    call print_hex32
    call newline

    mov si, msg_info_acpi
    call puts
    mov eax, [boot_info + 92]
    call print_hex32
    mov eax, [boot_info + 88]
    call print_hex32
    call newline

    mov si, msg_info_mmap
    call puts
    mov eax, [boot_info + 12]
    call print_hex32
    call newline
    ret

cmd_show_dir:
    call ensure_fat32_ready
    jc .fail

    mov si, msg_dir_root
    call puts
    mov eax, [root_cluster]
    call fat32_list_directory
    jc .fail

    mov si, msg_dir_boot
    call puts
    mov eax, [root_cluster]
    mov si, name_boot_dir
    call fat32_find_entry
    jc .fail
    mov eax, [found_cluster]
    call fat32_list_directory
    jc .fail
    ret

.fail:
    mov si, msg_fs_unavailable
    call puts
    ret

cmd_show_mmap:
    mov si, msg_mmap_header
    call puts

    xor bx, bx
    mov cx, [e820_count]
.entry_loop:
    cmp bx, cx
    jae .done

    mov si, msg_mmap_entry
    call puts
    mov ax, bx
    call print_hex16
    mov si, msg_mmap_base
    call puts
    mov ax, bx
    mov dx, 24
    mul dx
    mov di, e820_entries
    add di, ax

    mov eax, [di + 4]
    call print_hex32
    mov eax, [di]
    call print_hex32

    mov si, msg_mmap_length
    call puts
    mov eax, [di + 12]
    call print_hex32
    mov eax, [di + 8]
    call print_hex32

    mov si, msg_mmap_type
    call puts
    mov eax, [di + 16]
    call print_hex32
    call newline

    inc bx
    jmp .entry_loop

.done:
    ret

cmd_show_graphics:
    mov ax, 0x0013
    int 0x10

    mov ax, 0xA000
    mov es, ax
    xor di, di
    xor cx, cx
.fill:
    mov al, cl
    stosb
    inc cx
    cmp cx, 320 * 200
    jb .fill

    mov si, msg_graphics_done
    call puts_serial_only
    xor ah, ah
    int 0x16
    call clear_screen
    ret

init_boot_info:
    push di
    push ax
    cld
    mov di, boot_info
    mov cx, BOOTINFO_SIZE / 2
    xor ax, ax
    rep stosw
    pop ax
    pop di

    mov dword [boot_info + 0], BOOTINFO_MAGIC
    mov dword [boot_info + 4], BOOTINFO_VERSION
    mov dword [boot_info + 8], E820_ENTRY_SIZE
    mov dword [boot_info + 12], 0
    mov dword [boot_info + 16], e820_entries
    mov dword [boot_info + 20], 0
    mov dword [boot_info + 48], 0
    mov dword [boot_info + 52], 0
    mov eax, FAT32_PARTITION_LBA
    mov [boot_info + 56], eax
    mov dword [boot_info + 60], 0
    mov dword [boot_info + 72], KERNEL_LOAD_PHYS
    mov dword [boot_info + 76], 0
    mov dword [boot_info + 80], 0
    mov dword [boot_info + 84], 0
    mov dword [boot_info + 88], 0
    mov dword [boot_info + 92], 0
    movzx eax, byte [boot_drive]
    mov [boot_info + 48], eax
    ret

collect_memory_map:
    pushad
    xor ebx, ebx
    xor bp, bp
    mov di, e820_entries

.loop:
    mov eax, 0xE820
    mov edx, 0x534D4150
    mov ecx, E820_ENTRY_SIZE
    mov dword [di + 20], 1
    int 0x15
    jc .done
    cmp eax, 0x534D4150
    jne .done

    inc bp
    add di, E820_ENTRY_SIZE
    cmp bp, E820_MAX_ENTRIES
    jae .done
    test ebx, ebx
    jnz .loop

.done:
    mov [e820_count], bp
    movzx eax, bp
    mov [boot_info + 12], eax
    popad
    ret

detect_acpi_rsdp:
    pushad
    xor eax, eax
    mov ax, [0x040E]
    shl eax, 4
    test eax, eax
    jz .bios_scan

    mov edi, eax
    mov ecx, 1024 / 16
    call scan_rsdp
    jc .bios_scan
    jmp .found

.bios_scan:
    mov edi, 0x000E0000
    mov ecx, 0x20000 / 16
    call scan_rsdp
    jc .not_found

.found:
    mov [boot_info + 88], eax
    mov [boot_info + 92], edx
    jmp .done

.not_found:
    mov dword [boot_info + 88], 0
    mov dword [boot_info + 92], 0

.done:
    popad
    ret

scan_rsdp:
    push esi
    push ebx
.scan_loop:
    mov esi, edi
    mov ebx, rsdp_signature
    mov al, [esi]
    cmp al, [ebx]
    jne .next
    mov al, [esi + 1]
    cmp al, [ebx + 1]
    jne .next
    mov al, [esi + 2]
    cmp al, [ebx + 2]
    jne .next
    mov al, [esi + 3]
    cmp al, [ebx + 3]
    jne .next
    mov al, [esi + 4]
    cmp al, [ebx + 4]
    jne .next
    mov al, [esi + 5]
    cmp al, [ebx + 5]
    jne .next
    mov al, [esi + 6]
    cmp al, [ebx + 6]
    jne .next
    mov al, [esi + 7]
    cmp al, [ebx + 7]
    jne .next

    mov eax, edi
    xor edx, edx
    clc
    pop ebx
    pop esi
    ret

.next:
    add edi, 16
    loop .scan_loop
    stc
    pop ebx
    pop esi
    ret

fat32_init:
    pushad
    xor ax, ax
    mov es, ax
    mov eax, 0
    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    jc .fail

    mov eax, [sector_buffer + 446 + 8]
    mov [partition_lba], eax
    mov [boot_info + 56], eax

    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    jc .fail

    mov ax, [sector_buffer + 11]
    cmp ax, 512
    jne .fail
    mov [bytes_per_sector], ax

    mov al, [sector_buffer + 13]
    mov [sectors_per_cluster], al
    mov ax, [sector_buffer + 14]
    mov [reserved_sectors], ax
    mov al, [sector_buffer + 16]
    mov [fat_count], al
    mov eax, [sector_buffer + 36]
    mov [sectors_per_fat], eax
    mov eax, [sector_buffer + 44]
    mov [root_cluster], eax

    movzx eax, word [reserved_sectors]
    add eax, [partition_lba]
    mov [fat_start_lba], eax

    movzx eax, byte [fat_count]
    mov ecx, [sectors_per_fat]
    mul ecx
    add eax, [fat_start_lba]
    mov [data_start_lba], eax

    popad
    clc
    ret

.fail:
    popad
    stc
    ret

fat32_find_entry:
    pushad
    mov [search_name_ptr], si
    mov [search_cluster], eax

.cluster_loop:
    mov eax, [search_cluster]
    call cluster_to_lba
    mov [cluster_lba_cache], eax
    xor dx, dx

.sector_loop:
    push es
    xor ax, ax
    mov es, ax
    mov eax, [cluster_lba_cache]
    add eax, edx
    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    pop es
    jc .not_found

    xor di, di
.entry_loop:
    mov al, [sector_buffer + di]
    cmp al, 0x00
    je .not_found
    cmp al, 0xE5
    je .next_entry
    cmp byte [sector_buffer + di + 11], 0x0F
    je .next_entry

    push di
    mov si, [search_name_ptr]
    mov bp, 11
.cmp_loop:
    mov al, [si]
    cmp al, [sector_buffer + di]
    jne .cmp_fail
    inc si
    inc di
    dec bp
    jnz .cmp_loop
    pop di

    mov al, [sector_buffer + di + 11]
    mov [found_attr], al
    mov ax, [sector_buffer + di + 20]
    shl eax, 16
    mov ax, [sector_buffer + di + 26]
    mov [found_cluster], eax
    mov eax, [sector_buffer + di + 28]
    mov [found_size], eax
    popad
    clc
    ret

.cmp_fail:
    pop di

.next_entry:
    add di, 32
    cmp di, 512
    jb .entry_loop

    inc dx
    movzx ax, byte [sectors_per_cluster]
    cmp dx, ax
    jb .sector_loop

    mov eax, [search_cluster]
    call fat32_next_cluster
    jc .not_found
    mov [search_cluster], eax
    cmp eax, FAT32_EOC
    jb .cluster_loop

.not_found:
    popad
    stc
    ret

fat32_load_file:
    pushad
    mov [load_cluster], eax
    mov eax, [kernel_file_size]
    mov [bytes_remaining], eax
    mov word [load_segment], KERNEL_FILE_SEG

.cluster_loop:
    mov eax, [load_cluster]
    call cluster_to_lba
    mov [cluster_lba_cache], eax
    xor dx, dx

.read_sectors:
    mov eax, [bytes_remaining]
    test eax, eax
    jz .done

    mov ax, [load_segment]
    mov es, ax
    mov eax, [cluster_lba_cache]
    add eax, edx
    mov cx, 1
    xor bx, bx
    call read_lba
    jc .fail

    add word [load_segment], 0x20
    mov eax, [bytes_remaining]
    cmp eax, 512
    jbe .last_chunk
    sub dword [bytes_remaining], 512
    jmp .bump_sector

.last_chunk:
    mov dword [bytes_remaining], 0

.bump_sector:
    inc dx
    movzx ax, byte [sectors_per_cluster]
    cmp dx, ax
    jb .read_sectors

    mov eax, [load_cluster]
    call fat32_next_cluster
    jc .done
    mov [load_cluster], eax
    cmp eax, FAT32_EOC
    jb .cluster_loop

.done:
    xor ax, ax
    mov es, ax
    popad
    clc
    ret

.fail:
    xor ax, ax
    mov es, ax
    popad
    stc
    ret

fat32_list_directory:
    pushad
    mov [search_cluster], eax

.cluster_loop:
    mov eax, [search_cluster]
    call cluster_to_lba
    mov [cluster_lba_cache], eax
    xor dx, dx

.sector_loop:
    push es
    xor ax, ax
    mov es, ax
    mov eax, [cluster_lba_cache]
    add eax, edx
    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    pop es
    jc .fail

    xor di, di
.entry_loop:
    mov al, [sector_buffer + di]
    cmp al, 0x00
    je .done
    cmp al, 0xE5
    je .next_entry
    cmp al, '.'
    je .next_entry
    cmp byte [sector_buffer + di + 11], 0x0F
    je .next_entry

    push di
    call print_short_name
    pop di
    test byte [sector_buffer + di + 11], 0x10
    jz .line_end
    mov al, '/'
    call putc
.line_end:
    call newline

.next_entry:
    add di, 32
    cmp di, 512
    jb .entry_loop

    inc dx
    movzx ax, byte [sectors_per_cluster]
    cmp dx, ax
    jb .sector_loop

    mov eax, [search_cluster]
    call fat32_next_cluster
    jc .done
    mov [search_cluster], eax
    cmp eax, FAT32_EOC
    jb .cluster_loop

.done:
    popad
    clc
    ret

.fail:
    popad
    stc
    ret

print_short_name:
    push ax
    push bx
    push cx
    push si

    mov si, sector_buffer
    add si, di
    mov cx, 8
.name_loop:
    mov al, [si]
    cmp al, ' '
    je .skip_name_char
    call putc
.skip_name_char:
    inc si
    loop .name_loop

    mov bx, si
    mov cx, 3
.find_ext:
    mov al, [si]
    cmp al, ' '
    jne .has_ext
    inc si
    loop .find_ext
    jmp .done

.has_ext:
    mov al, '.'
    call putc
    mov si, bx
    mov cx, 3
.ext_loop:
    mov al, [si]
    cmp al, ' '
    je .skip_ext_char
    call putc
.skip_ext_char:
    inc si
    loop .ext_loop

.done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

fat32_next_cluster:
    pushad
    mov edx, eax
    shl edx, 2
    push es
    xor ax, ax
    mov es, ax
    mov eax, [fat_start_lba]
    mov ecx, edx
    shr ecx, 9
    add eax, ecx
    mov cx, 2
    mov bx, fat_buffer
    call read_lba
    pop es
    jc .fail

    and edx, 511
    mov esi, fat_buffer
    add esi, edx
    mov eax, [esi]
    and eax, 0x0FFFFFFF
    mov [next_cluster_result], eax
    popad
    mov eax, [next_cluster_result]
    clc
    ret

.fail:
    popad
    stc
    ret

cluster_to_lba:
    push edx
    push ecx
    sub eax, 2
    xor edx, edx
    movzx ecx, byte [sectors_per_cluster]
    mul ecx
    add eax, [data_start_lba]
    pop ecx
    pop edx
    ret

load_elf64:
    pushad
    push es
    mov ax, KERNEL_FILE_SEG
    mov es, ax

    cmp dword [es:KERNEL_FILE_OFFSET], 0x464C457F
    jne .bad_header
    cmp byte [es:KERNEL_FILE_OFFSET + 4], 2
    jne .bad_header
    cmp word [es:KERNEL_FILE_OFFSET + 18], 0x3E
    jne .bad_header

    mov esi, [es:KERNEL_FILE_OFFSET + 24]
    mov ebx, [es:KERNEL_FILE_OFFSET + 32]
    movzx ecx, word [es:KERNEL_FILE_OFFSET + 54]
    movzx edx, word [es:KERNEL_FILE_OFFSET + 56]
    cmp edx, 1
    jb .bad_header
    cmp ecx, 56
    jb .bad_header
    cmp ebx, [kernel_file_size]
    jae .bad_header

    mov eax, [es:ebx + KERNEL_FILE_OFFSET + 8]
    cmp eax, 0x1000
    jne .bad_header

    cmp dword [es:ebx + KERNEL_FILE_OFFSET + 0], 1
    jne .bad_header
    cmp dword [es:ebx + KERNEL_FILE_OFFSET + 24], KERNEL_LOAD_PHYS
    jne .bad_header

    mov eax, [es:ebx + KERNEL_FILE_OFFSET + 8]
    add eax, [es:ebx + KERNEL_FILE_OFFSET + 32]
    jc .bad_header
    cmp eax, [kernel_file_size]
    ja .bad_header

    pop es
    mov [boot_info + 64], esi
    mov dword [boot_info + 68], 0
    mov dword [boot_info + 72], KERNEL_LOAD_PHYS
    mov dword [boot_info + 76], 0
    mov eax, [kernel_file_size]
    mov [boot_info + 80], eax
    mov dword [boot_info + 84], 0
    popad
    clc
    ret

.bad_header:
    mov eax, [es:KERNEL_FILE_OFFSET]
    mov [debug_elf_magic], eax
    movzx eax, byte [es:KERNEL_FILE_OFFSET + 4]
    mov [debug_elf_class], eax
    movzx eax, word [es:KERNEL_FILE_OFFSET + 18]
    mov [debug_elf_machine], eax
    pop es
    mov si, msg_elf_bad_header
    call puts_serial_only
    mov si, msg_elf_magic
    call puts_serial_only
    mov eax, [debug_elf_magic]
    call print_hex32
    call newline
    mov si, msg_elf_class
    call puts_serial_only
    mov eax, [debug_elf_class]
    call print_hex32
    call newline
    mov si, msg_elf_machine
    call puts_serial_only
    mov eax, [debug_elf_machine]
    call print_hex32
    call newline
    popad
    stc
    ret

.fail:
    popad
    stc
    ret

enter_long_mode:
    pushad
    cld
    xor ax, ax
    mov es, ax
    mov di, PAGE_TABLE_PML4
    mov cx, (4096 * 3) / 2
    xor ax, ax
    rep stosw

    mov dword [PAGE_TABLE_PML4], PAGE_TABLE_PDPT | 0x03
    mov dword [PAGE_TABLE_PDPT], PAGE_TABLE_PD | 0x03
    mov dword [PAGE_TABLE_PD], 0x00000083

    lgdt [gdt_descriptor]

    mov eax, cr4
    or eax, 0x20
    mov cr4, eax

    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x00000100
    wrmsr

    mov eax, PAGE_TABLE_PML4
    mov cr3, eax

    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax

    jmp 0x08:long_mode_entry

read_lba:
    push ax
    push dx
    mov [disk_packet.sector_count], cx
    mov [disk_packet.buffer_offset], bx
    mov [disk_packet.buffer_segment], es
    mov [disk_packet.lba_low], eax
    mov dword [disk_packet.lba_high], 0
    mov si, disk_packet
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    pop dx
    pop ax
    ret

read_line:
    mov di, command_buffer
    xor cx, cx
.key:
    xor ah, ah
    int 0x16
    cmp al, 13
    je .done
    cmp al, 8
    jne .printable
    cmp cx, 0
    je .key
    dec di
    dec cx
    mov al, 8
    call putc
    mov al, ' '
    call putc
    mov al, 8
    call putc
    jmp .key

.printable:
    cmp al, 'a'
    jb .store
    cmp al, 'z'
    ja .store
    sub al, 32

.store:
    cmp al, 32
    jb .key
    cmp al, 126
    ja .key
    cmp cx, 63
    jae .key
    mov [di], al
    inc di
    inc cx
    call putc
    jmp .key

.done:
    mov byte [di], 0
    call newline
    ret

strings_equal:
    push si
    push di
.loop:
    mov al, [si]
    cmp al, [di]
    jne .no
    test al, al
    jz .yes
    inc si
    inc di
    jmp .loop
.yes:
    pop di
    pop si
    clc
    ret
.no:
    pop di
    pop si
    stc
    ret

newline:
    mov al, 13
    call putc
    mov al, 10
    call putc
    ret

puts:
    lodsb
    test al, al
    jz .done
    call putc
    jmp puts
.done:
    ret

puts_serial_only:
    lodsb
    test al, al
    jz .done
    call serial_write
    jmp puts_serial_only
.done:
    ret

putc:
    push ax
    push bx
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    pop bx
    pop ax
    call serial_write
    ret

serial_init:
    mov dx, COM1 + 1
    xor al, al
    out dx, al
    mov dx, COM1 + 3
    mov al, 0x80
    out dx, al
    mov dx, COM1 + 0
    mov al, 0x03
    out dx, al
    mov dx, COM1 + 1
    xor al, al
    out dx, al
    mov dx, COM1 + 3
    mov al, 0x03
    out dx, al
    mov dx, COM1 + 2
    mov al, 0xC7
    out dx, al
    mov dx, COM1 + 4
    mov al, 0x0B
    out dx, al
    ret

serial_write:
    push dx
    push ax
    mov dx, COM1 + 5
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    pop ax
    mov dx, COM1
    out dx, al
    pop dx
    ret

print_hex16:
    push bx
    mov bx, ax
    mov al, bh
    call print_hex8
    mov al, bl
    call print_hex8
    pop bx
    ret

print_hex32:
    push ax
    push bx
    push cx
    push dx
    mov cx, 8
.nibble:
    rol eax, 4
    mov bl, al
    and bl, 0x0F
    mov al, bl
    call print_hex_nibble
    loop .nibble
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_hex8:
    push ax
    mov ah, al
    shr al, 4
    call print_hex_nibble
    mov al, ah
    and al, 0x0F
    call print_hex_nibble
    pop ax
    ret

print_hex_nibble:
    and al, 0x0F
    cmp al, 9
    jbe .digit
    add al, 7
.digit:
    add al, '0'
    call putc
    ret

disk_packet:
    db 0x10
    db 0
.sector_count dw 0
.buffer_offset dw 0
.buffer_segment dw 0
.lba_low dd 0
.lba_high dd 0

banner db 'stage2: shell ready', 13, 10, 0
prompt db '> ', 0
msg_unknown db 'unknown command', 13, 10, 0
msg_autoboot db 'Press any key for shell. Autoboot in 15 seconds...', 13, 10, 0
msg_autobooting db 'Autobooting kernel...', 13, 10, 0
msg_shell db 'Interactive shell enabled.', 13, 10, 0
msg_kernel_load db 'Loading /BOOT/KERNEL.ELF...', 13, 10, 0
msg_kernel_jump db 'Entering 64-bit kernel.', 13, 10, 0
msg_kernel_fail db 'Kernel load failed.', 13, 10, 0
msg_kernel_too_large db 'Kernel file exceeds stage2 buffer.', 13, 10, 0
msg_step_fat_ready db 'stage2: FAT ready', 13, 10, 0
msg_step_kernel_found db 'stage2: kernel located', 13, 10, 0
msg_step_file_loaded db 'stage2: kernel file copied', 13, 10, 0
msg_step_elf_loaded db 'stage2: ELF segments loaded', 13, 10, 0
msg_elf_bad_header db 'stage2: ELF header rejected', 13, 10, 0
msg_elf_magic db 'stage2: magic 0x', 0
msg_elf_class db 'stage2: class 0x', 0
msg_elf_machine db 'stage2: machine 0x', 0
msg_graphics_done db 'Graphics test drawn. Press any key to return.', 0
help_text db 'HELP  CLEAR  INFO  DIR  MMAP  GFX  BOOT  REBOOT', 13, 10, 0
msg_info_boot_drive db 'boot drive: 0x', 0
msg_info_partition db 'partition lba: 0x', 0
msg_info_root_cluster db 'root cluster: 0x', 0
msg_info_acpi db 'acpi rsdp: 0x', 0
msg_info_mmap db 'mmap entries: 0x', 0
msg_fs_unavailable db 'FAT32 volume unavailable.', 13, 10, 0
msg_dir_root db 'root:', 13, 10, 0
msg_dir_boot db '/BOOT:', 13, 10, 0
msg_mmap_header db 'e820 memory map:', 13, 10, 0
msg_mmap_entry db 'entry ', 0
msg_mmap_base db ' base 0x', 0
msg_mmap_length db ' length 0x', 0
msg_mmap_type db ' type 0x', 0
rsdp_signature db 'RSD PTR '

cmd_help db 'HELP', 0
cmd_clear db 'CLEAR', 0
cmd_info db 'INFO', 0
cmd_dir db 'DIR', 0
cmd_mmap db 'MMAP', 0
cmd_gfx db 'GFX', 0
cmd_boot db 'BOOT', 0
cmd_reboot db 'REBOOT', 0
name_boot_dir db 'BOOT       '
name_kernel_file db 'KERNEL  ELF'

boot_drive db 0
bytes_per_sector dw 0
reserved_sectors dw 0
sectors_per_cluster db 0
fat_count db 0
fat32_ready db 0
found_attr db 0
load_segment dw 0
e820_count dw 0

partition_lba dd 0
fat_start_lba dd 0
data_start_lba dd 0
sectors_per_fat dd 0
root_cluster dd 0
cluster_lba_cache dd 0
current_directory_cluster dd 0
search_cluster dd 0
found_cluster dd 0
found_size dd 0
kernel_file_size dd 0
bytes_remaining dd 0
next_cluster_result dd 0
load_cluster dd 0
debug_elf_magic dd 0
debug_elf_class dd 0
debug_elf_machine dd 0
search_name_ptr dw 0

align 8
boot_info:
    times BOOTINFO_SIZE db 0

align 16
gdt64:
    dq 0
    dq 0x00AF9A000000FFFF
    dq 0x00AF92000000FFFF
gdt_descriptor:
    dw gdt_descriptor - gdt64 - 1
    dd gdt64

[BITS 64]
long_mode_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov rsp, 0x90000
    mov rdi, boot_info
    mov rax, KERNEL_LOAD_PHYS
    jmp rax

[BITS 16]

align 16
sector_buffer:
    times 512 db 0

align 16
fat_buffer:
    times 1024 db 0

align 16
e820_entries:
    times E820_ENTRY_SIZE * E820_MAX_ENTRIES db 0

command_buffer:
    times 64 db 0

align 16
stage2_stack:
    times 4096 db 0
stage2_stack_top:

times (128 * 512) - ($ - $$) db 0
