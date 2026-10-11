/* CoreMark portme.h —— RISC-V RV32IM, 自研 7 级流水 CPU */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include "coremark_build_info.h" /* generated from the build's actual options */

/* ---- 类型定义 ---- */
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef double         ee_f32;
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
typedef ee_u32         ee_ptr_int;
typedef size_t         ee_size_t;

#ifndef NULL
#define NULL ((void *)0)
#endif

/* ---- 平台特性 ---- */
#define HAS_FLOAT          1     /* 用 ee_f32 (double) 算时间，soft-float */
#define HAS_TIME_H         0
#define USE_CLOCK          0
#define HAS_STDIO          1
/* HAS_PRINTF=0：不用 libc 的 printf，改用端口自己的 ee_printf（port/ee_printf.c）。
 * 原因：newlib-nano 的 printf 不支持 %f，而 -u _printf_float 会把 .text 撑到
 * 40680 字节 > 32KB IROM 直接链接失败；CoreMark 只用 %s %d %u %lu %04x %f。 */
#define HAS_PRINTF         0

#if !HAS_PRINTF
/* 端口自带的极简 printf，实现在 port/ee_printf.c，输出到 magic UART */
int ee_printf(const char *fmt, ...);
#endif

#define MAIN_HAS_NOARGC    1
#define MAIN_HAS_NORETURN  0

#define MEM_METHOD         MEM_STATIC
#define MEM_LOCATION       "STATIC; code=IROM(BRAM), data=DRAM(BRAM); memory/core clock=1:1"

#define SEED_METHOD        SEED_VOLATILE
#define ALIGN_64BIT        0     /* RV32 */

/* ---- 单线程 ---- */
#define MULTITHREAD        1
#define USE_PTHREAD        0
#define USE_FORK           0
#define USE_SOCKET         0

/* ---- 迭代次数（仿真用小值；上板可改大）---- */
#ifndef ITERATIONS
#define ITERATIONS 10
#endif

/* ---- 编译信息 ---- */
#define COMPILER_VERSION "GCC " __VERSION__
#define COMPILER_FLAGS   FLAGS_STR

/* ---- 时间单位：用 mcycle CSR ---- */
typedef ee_u32 CORE_TICKS;

#ifndef CPU_HZ
#define CPU_HZ 100000000U       /* 仿真台 100 MHz */
#endif
#define EE_TICKS_PER_SEC CPU_HZ

/* ---- portable struct（CoreMark 内部用） ---- */
typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

/* ---- 给 core_main.c 看的全局符号 ---- */
extern ee_u32 default_num_contexts;

/* portable_init / portable_fini 的声明在 coremark.h 里 */

#endif
