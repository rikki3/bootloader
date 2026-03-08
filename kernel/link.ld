ENTRY(kernel_entry)

PHDRS {
    kernel PT_LOAD FLAGS(7);
}

SECTIONS {
    . = 0x00201000;

    .text : ALIGN(0x1000) {
        *(.text*)
        *(.rodata*)
        *(.data*)
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } :kernel

    __kernel_end = .;

    /DISCARD/ : {
        *(.comment*)
        *(.eh_frame*)
        *(.note*)
    }
}
