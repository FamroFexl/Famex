ENTRY(_start)

SECTIONS
{
    /* Start program at 1 MiB */
    . = 0x100000;

    /* Code section */
    .text : {
            *(.text .text.*)
        } :text

    /* Read-only data */
    .rodata ALIGN(0x1000) : {
            *(.rodata .rodata.*)
        } :rodata

    /* Initialized data */
     .data ALIGN(0x1000) : {
            *(.data .data.*)
        } :data

    /* Zero-initialized data */
    .bss ALIGN(0x1000) : {
            *(.bss .bss.*)
            *(COMMON)
    } :data
}