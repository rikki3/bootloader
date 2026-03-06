ENTRY(kernel_entry)

PHDRS {
    kernel PT_LOAD FLAGS(7);
}

SECTIONS {
    . = 0x00021000;

    .text : ALIGN(0x1000) {
        *(.text*)
        *(.rodata*)
        *(.data*)
        *(.bss*)
        *(COMMON)
    } :kernel

    /DISCARD/ : {
        *(.comment*)
        *(.eh_frame*)
        *(.note*)
    }
}
