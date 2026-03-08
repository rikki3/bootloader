[BITS 16]
[ORG 0x8000]

%define COM1                0x3F8
%define KERNEL_FILE_PHYS    0x00020000
%define KERNEL_FILE_MAX_SIZE 0x000E0000
%define KERNEL_LOAD_PHYS    0x00201000
%define VGA_FB_PHYS         0x000A0000
%define VGA_WIDTH           320
%define VGA_HEIGHT          200
%define VGA_PITCH           320
%define VGA_BPP             8
%define MAX_BOOT_PHYS       0x08000000
%define PAGE_TABLE_PML4     0x1000
%define PAGE_TABLE_PDPT     0x2000
%define PAGE_TABLE_PD       0x3000
%define E820_ENTRY_SIZE     24
%define E820_MAX_ENTRIES    64
%define BOOTINFO_MAGIC      0x31544942
%define BOOTINFO_VERSION    2
%define BOOTINFO_SIZE       112
%define FAT32_EOC           0x0FFFFFF8
%define FAT32_PARTITION_LBA 2048
%define AUTOBOOT_TICKS      273
%define WAD_METADATA_LBA    129
%define WAD_METADATA_MAGIC  0x4D444157
%define WAD_BOUNCE_PHYS     0x00004000
%define WAD_BOUNCE_SECTORS  32

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
    mov si, msg_wad_load
    call puts
    call prepare_wad_from_fat32
    jc .fail

    call copy_wad_from_fat32
    jc .fail
    mov si, msg_step_wad_loaded
    call puts_serial_only

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
    mov ax, 0x0013
    int 0x10
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

prepare_wad_from_fat32:
    mov dword [wad_start_lba], 0
    mov dword [wad_file_size], 0
    call load_wad_metadata
    jc prepare_wad_metadata_fail
    mov si, msg_step_wad_found
    call puts_serial_only

    call validate_wad_header
    jc prepare_wad_invalid

    call select_wad_load_region
    jc prepare_wad_no_mem

    clc
    ret

copy_wad_from_fat32:
    mov eax, [wad_start_lba]
    test eax, eax
    jz .copy_not_ready
    mov word [wad_progress_sectors], 0
    mov si, msg_wad_copying
    call puts
    mov eax, [wad_start_lba]

    call load_wad_from_disk_to_high_memory
    jc copy_wad_fail

    mov eax, [wad_load_phys]
    mov [boot_info + 96], eax
    mov dword [boot_info + 100], 0
    mov eax, [wad_file_size]
    mov [boot_info + 104], eax
    mov dword [boot_info + 108], 0
    clc
    ret

.copy_not_ready:
    mov si, msg_wad_not_ready
    call puts
    stc
    ret

prepare_wad_metadata_fail:
    mov si, msg_wad_metadata_fail
    call puts
    stc
    ret

prepare_wad_invalid:
    mov si, msg_wad_invalid
    call puts
    stc
    ret

prepare_wad_no_mem:
    mov si, msg_wad_no_mem
    call puts
    stc
    ret

copy_wad_fail:
    mov si, msg_wad_fail
    call puts
    stc
    ret

load_wad_metadata:
    pushad
    push es
    xor ax, ax
    mov es, ax
    mov eax, WAD_METADATA_LBA
    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    pop es
    jc .fail

    cmp dword [sector_buffer + 0], WAD_METADATA_MAGIC
    jne .fail

    mov eax, [sector_buffer + 4]
    test eax, eax
    jz .fail
    mov [wad_start_lba], eax

    mov eax, [sector_buffer + 8]
    cmp eax, 12
    jb .fail
    mov [wad_file_size], eax

    popad
    clc
    ret

.fail:
    popad
    stc
    ret

validate_wad_header:
    pushad
    push es
    xor ax, ax
    mov es, ax
    mov eax, [wad_start_lba]
    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    pop es
    jc .fail

    mov al, [sector_buffer + 0]
    cmp al, 'I'
    je .check_rest
    cmp al, 'P'
    jne .fail

.check_rest:
    cmp byte [sector_buffer + 1], 'W'
    jne .fail
    cmp byte [sector_buffer + 2], 'A'
    jne .fail
    cmp byte [sector_buffer + 3], 'D'
    jne .fail

    mov eax, [sector_buffer + 4]
    test eax, eax
    jz .fail
    mov ecx, 16
    mul ecx
    jc .fail
    add eax, [sector_buffer + 8]
    jc .fail
    cmp eax, [wad_file_size]
    ja .fail

    popad
    clc
    ret

.fail:
    popad
    stc
    ret

select_wad_load_region:
    pushad
    xor ebx, ebx
    xor si, si
    mov ecx, [wad_file_size]
    add ecx, 0x0FFF
    and ecx, 0xFFFFF000

.entry_loop:
    cmp si, [e820_count]
    jae .done

    mov ax, si
    mov dx, E820_ENTRY_SIZE
    mul dx
    mov di, e820_entries
    add di, ax

    cmp dword [di + 16], 1
    jne .next
    cmp dword [di + 4], 0
    jne .next
    cmp dword [di + 12], 0
    jne .next

    mov eax, [di + 0]
    cmp eax, MAX_BOOT_PHYS
    jae .next
    cmp eax, 0x00100000
    jae .have_start
    mov eax, 0x00100000

.have_start:
    mov edx, [di + 0]
    add edx, [di + 8]
    jc .cap_end
    cmp edx, MAX_BOOT_PHYS
    jbe .have_end

.cap_end:
    mov edx, MAX_BOOT_PHYS

.have_end:
    cmp edx, eax
    jbe .next

    mov ebp, edx
    sub ebp, ecx
    jc .next
    and ebp, 0xFFFFF000
    cmp ebp, eax
    jb .next
    cmp ebp, ebx
    jbe .next
    mov ebx, ebp

.next:
    inc si
    jmp .entry_loop

.done:
    mov [wad_load_phys], ebx
    popad
    cmp dword [wad_load_phys], 0
    jz .fail
    clc
    ret

.fail:
    stc
    ret

load_wad_from_disk_to_high_memory:
    pushad
    mov [wad_current_lba], eax
    mov eax, [wad_file_size]
    mov [bytes_remaining], eax
    mov eax, [wad_load_phys]
    mov [high_copy_dest], eax

.read_sectors:
    mov eax, [bytes_remaining]
    test eax, eax
    jz .done

    mov ecx, eax
    add ecx, 511
    shr ecx, 9
    cmp ecx, WAD_BOUNCE_SECTORS
    jbe .have_sector_count
    mov ecx, WAD_BOUNCE_SECTORS

.have_sector_count:
    mov eax, ecx
    shl eax, 9
    cmp eax, [bytes_remaining]
    jbe .have_copy_bytes
    mov eax, [bytes_remaining]

.have_copy_bytes:
    mov [copy_bytes], eax

    push es
    xor ax, ax
    mov es, ax
    mov eax, [wad_current_lba]
    mov bx, WAD_BOUNCE_PHYS
    call read_lba
    pop es
    jc .fail

    mov dword [low_copy_source], WAD_BOUNCE_PHYS
    call copy_sector_buffer_to_high_memory
    mov eax, [bytes_remaining]
    sub eax, [copy_bytes]
    mov [bytes_remaining], eax
    movzx eax, cx
    add [wad_current_lba], eax
    add [wad_progress_sectors], cx
    mov ax, [wad_progress_sectors]
    test ax, 0x00FF
    jnz .skip_progress
    mov al, '.'
    call putc
.skip_progress:
    jmp .read_sectors

.done:
    cmp word [wad_progress_sectors], 0
    je .no_newline
    call newline
.no_newline:
    popad
    clc
    ret

.fail:
    popad
    stc
    ret

copy_sector_buffer_to_high_memory:
    pushad
    pushf
    cmp byte [copy_debug_state], 0
    jne .skip_copy_msg
    mov si, msg_step_copy_sector
    call puts_serial_only
    mov byte [copy_debug_state], 1
.skip_copy_msg:
    call enter_unreal_mode
    cmp byte [copy_debug_state], 1
    jne .skip_unreal_msg
    mov si, msg_step_copy_unreal
    call puts_serial_only
    mov byte [copy_debug_state], 2
.skip_unreal_msg:
    xor ax, ax
    mov ds, ax
    mov esi, [low_copy_source]
    mov edi, [high_copy_dest]
    mov ecx, [copy_bytes]
    mov ebx, ecx
    shr ecx, 2

.copy_dwords:
    test ecx, ecx
    jz .copy_bytes
    mov eax, [esi]
    mov [gs:edi], eax
    add esi, 4
    add edi, 4
    dec ecx
    jmp .copy_dwords

.copy_bytes:
    mov ecx, ebx
    and ecx, 3

.copy_byte_loop:
    test ecx, ecx
    jz .done
    mov al, [esi]
    mov [gs:edi], al
    inc esi
    inc edi
    dec ecx
    jmp .copy_byte_loop

.done:
    mov [high_copy_dest], edi
    xor ax, ax
    mov gs, ax
    popf
    popad
    ret

enter_unreal_mode:
    cli
    lgdt [unreal_gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x0008:unreal_mode_pm

unreal_mode_pm:
    mov ax, 0x10
    mov gs, ax
    mov eax, cr0
    and eax, 0xFFFFFFFE
    mov cr0, eax
    jmp 0x0000:unreal_mode_rm

unreal_mode_rm:
unreal_mode_done:
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
    mov dword [boot_info + 24], VGA_FB_PHYS
    mov dword [boot_info + 28], 0
    mov dword [boot_info + 32], VGA_WIDTH
    mov dword [boot_info + 36], VGA_HEIGHT
    mov dword [boot_info + 40], VGA_PITCH
    mov dword [boot_info + 44], VGA_BPP
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
    mov dword [boot_info + 96], 0
    mov dword [boot_info + 100], 0
    mov dword [boot_info + 104], 0
    mov dword [boot_info + 108], 0
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
    mov byte [fat32_find_error], 1
    mov [search_name_ptr], si
    mov [search_cluster], eax

.cluster_loop:
    mov eax, [search_cluster]
    call cluster_to_lba
    mov [cluster_lba_cache], eax
    xor edx, edx

.sector_loop:
    push es
    xor ax, ax
    mov es, ax
    movzx edx, dx
    mov eax, [cluster_lba_cache]
    add eax, edx
    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    pop es
    jc .read_fail

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
    xor eax, eax
    xor edx, edx
    mov dx, [sector_buffer + di + 20]
    shl edx, 16
    mov ax, [sector_buffer + di + 26]
    or eax, edx
    mov [found_cluster], eax
    mov eax, [sector_buffer + di + 28]
    mov [found_size], eax
    mov byte [fat32_find_error], 0
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
    jc .chain_fail
    mov [search_cluster], eax
    cmp eax, FAT32_EOC
    jb .cluster_loop

.read_fail:
    mov byte [fat32_find_error], 2
    popad
    stc
    ret

.chain_fail:
    mov byte [fat32_find_error], 3
    popad
    stc
    ret

.not_found:
    popad
    stc
    ret

fat32_load_file:
    pushad
    mov [load_cluster], eax
    mov eax, [kernel_file_size]
    mov [bytes_remaining], eax
    mov word [load_segment], 0x2000

.cluster_loop:
    mov eax, [load_cluster]
    call cluster_to_lba
    mov [cluster_lba_cache], eax
    xor edx, edx

.read_sectors:
    mov eax, [bytes_remaining]
    test eax, eax
    jz .done

    mov ax, [load_segment]
    mov es, ax
    movzx edx, dx
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

fat32_load_kernel_to_high_memory:
    pushad
    mov si, msg_step_kernel_copy_start
    call puts_serial_only
    mov [load_cluster], eax
    mov eax, [kernel_file_size]
    mov [bytes_remaining], eax
    mov dword [high_copy_dest], KERNEL_FILE_PHYS

.cluster_loop:
    mov eax, [load_cluster]
    call cluster_to_lba
    mov [cluster_lba_cache], eax
    xor edx, edx

.read_sectors:
    mov eax, [bytes_remaining]
    test eax, eax
    jz .done

    push es
    xor ax, ax
    mov es, ax
    movzx edx, dx
    mov eax, [cluster_lba_cache]
    add eax, edx
    mov cx, 1
    mov bx, sector_buffer
    call read_lba
    pop es
    jc .fail

    mov eax, [bytes_remaining]
    cmp eax, 512
    jbe .short_copy
    mov eax, 512

.short_copy:
    mov [copy_bytes], eax
    mov dword [low_copy_source], sector_buffer
    call copy_sector_buffer_to_high_memory
    mov eax, [bytes_remaining]
    sub eax, [copy_bytes]
    mov [bytes_remaining], eax

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
    popad
    clc
    ret

.fail:
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
    xor edx, edx

.sector_loop:
    push es
    xor ax, ax
    mov es, ax
    movzx edx, dx
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
    mov edi, KERNEL_FILE_PHYS
    cmp dword [edi], 0x464C457F
    jne .bad_header
    cmp byte [edi + 4], 2
    jne .bad_header
    cmp word [edi + 18], 0x3E
    jne .bad_header

    mov esi, [edi + 24]
    mov ebx, [edi + 32]
    movzx ecx, word [edi + 54]
    movzx edx, word [edi + 56]
    cmp edx, 1
    jb .bad_header
    cmp ecx, 56
    jb .bad_header
    cmp ebx, [kernel_file_size]
    jae .bad_header

    lea edx, [edi + ebx]
    mov eax, [edx + 8]
    cmp eax, 0x1000
    jne .bad_header

    cmp dword [edx + 0], 1
    jne .bad_header
    cmp dword [edx + 24], KERNEL_LOAD_PHYS
    jne .bad_header

    mov eax, [edx + 8]
    add eax, [edx + 32]
    jc .bad_header
    cmp eax, [kernel_file_size]
    ja .bad_header

    mov eax, [edx + 8]
    add eax, KERNEL_FILE_PHYS
    mov [low_copy_source], eax
    mov dword [high_copy_dest], KERNEL_LOAD_PHYS
    mov eax, [edx + 32]
    mov [copy_bytes], eax
    call copy_sector_buffer_to_high_memory

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
    mov eax, [edi]
    mov [debug_elf_magic], eax
    movzx eax, byte [edi + 4]
    mov [debug_elf_class], eax
    movzx eax, word [edi + 18]
    mov [debug_elf_machine], eax
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
    xor ebx, ebx
    mov di, PAGE_TABLE_PD
    mov cx, 64

.map_loop:
    mov eax, ebx
    or eax, 0x83
    mov [di], eax
    mov dword [di + 4], 0
    add ebx, 0x200000
    add di, 8
    loop .map_loop

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
    push ds
    push es
    pushad
    mov [disk_packet.sector_count], cx
    mov [disk_packet.buffer_offset], bx
    mov [disk_packet.buffer_segment], es
    mov [disk_packet.lba_low], eax
    mov dword [disk_packet.lba_high], 0
    mov si, disk_packet
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    popad
    pop es
    pop ds
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
msg_wad_load db 'Loading /DOOM2.WAD...', 13, 10, 0
msg_kernel_jump db 'Entering 64-bit kernel.', 13, 10, 0
msg_kernel_fail db 'Kernel load failed.', 13, 10, 0
msg_kernel_too_large db 'Kernel file exceeds stage2 buffer.', 13, 10, 0
msg_wad_not_found db 'DOOM2.WAD not found in the FAT32 root.', 13, 10, 0
msg_wad_dir_read_fail db 'Could not read the FAT32 root while locating DOOM2.WAD.', 13, 10, 0
msg_wad_fat_fail db 'FAT32 chain traversal failed while locating DOOM2.WAD.', 13, 10, 0
msg_wad_not_ready db 'DOOM2.WAD was not prepared before copy.', 13, 10, 0
msg_wad_metadata_fail db 'DOOM2.WAD metadata is missing from the image.', 13, 10, 0
msg_wad_invalid db 'DOOM2.WAD header is invalid.', 13, 10, 0
msg_wad_no_mem db 'No memory region below 128 MiB for DOOM2.WAD.', 13, 10, 0
msg_wad_fail db 'Failed to copy DOOM2.WAD into memory.', 13, 10, 0
msg_step_fat_ready db 'stage2: FAT ready', 13, 10, 0
msg_step_kernel_found db 'stage2: kernel located', 13, 10, 0
msg_step_kernel_copy_start db 'stage2: kernel copy start', 13, 10, 0
msg_step_wad_found db 'stage2: DOOM2.WAD located', 13, 10, 0
msg_step_file_loaded db 'stage2: kernel file copied', 13, 10, 0
msg_step_wad_loaded db 'stage2: DOOM2.WAD copied', 13, 10, 0
msg_wad_copying db 'Copying /DOOM2.WAD to RAM', 13, 10, 0
msg_step_elf_loaded db 'stage2: ELF segments loaded', 13, 10, 0
msg_step_copy_sector db 'stage2: sector copy entered', 13, 10, 0
msg_step_copy_unreal db 'stage2: unreal mode active', 13, 10, 0
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
name_wad_file db 'DOOM2   WAD'

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
wad_start_lba dd 0
wad_file_size dd 0
bytes_remaining dd 0
copy_bytes dd 0
next_cluster_result dd 0
wad_current_lba dd 0
load_cluster dd 0
wad_load_phys dd 0
high_copy_dest dd 0
low_copy_source dd 0
debug_elf_magic dd 0
debug_elf_class dd 0
debug_elf_machine dd 0
search_name_ptr dw 0
wad_progress_sectors dw 0
fat32_find_error db 0
copy_debug_state db 0
align 8

align 8
boot_info:
    times BOOTINFO_SIZE db 0

align 16
unreal_gdt:
    dq 0
    dq 0x00009A000000FFFF
    dq 0x00CF92000000FFFF
unreal_gdt_descriptor:
    dw unreal_gdt_descriptor - unreal_gdt - 1
    dd unreal_gdt

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
    mov rax, [boot_info + 64]
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
