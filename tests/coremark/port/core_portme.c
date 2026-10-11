/* CoreMark portme.c —— RV32IM, custom 7-stage CPU */
#include "coremark.h"
#include "core_portme.h"

/* CoreMark 要求的对齐工具：把指针 8 字节对齐（向上）*/
ee_u8 *align_mem(ee_u8 *memblock) {
    return (ee_u8 *)(((ee_ptr_int)memblock + 7) & ~7);
}

/* Official 2K seeds; volatile prevents compile-time workload evaluation. */
#if (PERFORMANCE_RUN + VALIDATION_RUN) != 1
#error "Select exactly one of PERFORMANCE_RUN=1 or VALIDATION_RUN=1"
#endif
#if TOTAL_DATA_SIZE != 2000
#error "Official performance/validation runs require TOTAL_DATA_SIZE=2000"
#endif
#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#else
volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

static CORE_TICKS start_ticks, stop_ticks;

static inline ee_u32 read_mcycle_lo(void) {
    ee_u32 v;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(v));
    return v;
}

void start_time(void) {
    start_ticks = read_mcycle_lo();
}

void stop_time(void) {
    stop_ticks = read_mcycle_lo();
}

CORE_TICKS get_time(void) {
    return (CORE_TICKS)(stop_ticks - start_ticks);
}

secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)ticks / (secs_ret)EE_TICKS_PER_SEC;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc; (void)argv;
    p->portable_id = 1;
    /* 把 cycle 计数器清零（让 ee_printf 自己的开销不算进去） */
    /* mcycle 在 reset 时已经为 0；这里不写也行 */
}

void portable_fini(core_portable *p) {
    (void)p;
    /* Report after the timed workload; strings come from the actual build. */
    ee_printf("CPU clock (Hz)   : %u\n", (ee_u32)CPU_HZ);
    ee_printf("Linker flags     : %s\n", LINKER_FLAGS_STR);
    ee_printf("Link libraries   : %s\n", LINK_LIBS_STR);
    ee_printf("C library        : %s\n", LIBC_NAME_STR);
    /* 让 testbench 看到 EXIT 信号 */
    volatile unsigned int *exit_p = (volatile unsigned int *)0xF0000004;
    *exit_p = 1u;
    while (1) { __asm__ volatile ("nop"); }
}
