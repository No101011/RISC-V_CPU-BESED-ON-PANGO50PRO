OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
    IROM (rx) : ORIGIN = 0x80000000, LENGTH = 32K
    DRAM (rw) : ORIGIN = 0x80100000, LENGTH = 128K
}
SECTIONS {
    .text : { KEEP(*(.text.init)) *(.text .text.*) } > IROM
    .data : { *(.data .data.* .rodata .rodata.*) } > DRAM
    .bss (NOLOAD) : { *(.bss .bss.*) *(COMMON) } > DRAM
    /DISCARD/ : { *(.comment) *(.note.*) *(.eh_frame*) }
}
