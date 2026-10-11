/* link.ld —— 自研 7 级流水 RV32IM CPU（Harvard：IROM 不可数据访问）
 *   IROM @ 0x80000000  (32KB = 8192 字，与 CPU 取指窗口 pc[14:2] 一致)  -- 仅 .text
 *   DRAM @ 0x80100000  (128KB)                    -- .rodata + .data + .bss + heap + stack
 *
 *   stack 顶端 = DRAM 顶端 (0x80120000)
 *
 *   ⚠️ .text 的基址必须是 0x80000000：
 *      CPU 复位 PC = 0x8000_0000（rtl/core/pc_reg.v:16），架构 PC 也由 myCPU 的 head_pc
 *      按 0x8000_0000 基址拼出。若链在 0（旧值），crt0 的 `auipc gp/sp` 会算到
 *      0x0010_xxxx / 0x0014_xxxx（不存在的区域），全局变量与栈全错，程序起不来。
 *   ⚠️ DRAM 取 128K：FPGA 侧 DRAM 已从 256KB 缩到 128KB（PGL50H 的 DRM 限制），
 *      栈顶随之从 0x80140000 变成 0x80120000。
 *   IROM LENGTH 取 32K：超出会直接在链接期报错，避免"程序比 ROM 大"到上板才发现。
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IROM (rx)  : ORIGIN = 0x80000000, LENGTH = 32K
    DRAM (rwx) : ORIGIN = 0x80100000, LENGTH = 128K
}

PROVIDE(__STACK_SIZE = 8K);
PROVIDE(__HEAP_SIZE  = 16K);

SECTIONS
{
    /* -------- 代码段：仅 .text 在 IROM -------- */
    .text : ALIGN(4) {
        _stext = .;
        KEEP(*(.text.init))         /* crt0 _start 入口必须在最前 */
        *(.text)
        *(.text.*)
        . = ALIGN(4);
        _etext = .;
    } > IROM

    /* -------- 只读数据：放 DRAM 因为 CPU 不能从 IROM 做 load -------- */
    .rodata : ALIGN(4) {
        _srodata = .;
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
        _erodata = .;
    } > DRAM

    /* -------- 已初始化数据 -------- */
    .data : ALIGN(4) {
        _sdata = .;
        *(.data)
        *(.data.*)
        . = ALIGN(8);
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata)
        *(.sdata.*)
        *(.gnu.linkonce.s.*)
        . = ALIGN(4);
        _edata = .;
    } > DRAM

    /* -------- BSS -------- */
    .bss (NOLOAD) : ALIGN(4) {
        _sbss = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > DRAM

    /* -------- heap -------- */
    . = ALIGN(8);
    _end = .;            /* _sbrk 起点 */
    PROVIDE(end = .);

    .heap (NOLOAD) : ALIGN(8) {
        _sheap = .;
        . = . + __HEAP_SIZE;
        . = ALIGN(8);
        _eheap = .;
    } > DRAM

    /* -------- stack（DRAM 顶部） -------- */
    .stack ORIGIN(DRAM) + LENGTH(DRAM) - __STACK_SIZE (NOLOAD) : ALIGN(16) {
        _sstack = .;
        . = . + __STACK_SIZE;
        . = ALIGN(16);
        _estack = .;
    } > DRAM

    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.comment)
        *(.note.*)
        *(.debug_*)
    }
}
