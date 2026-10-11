/* ee_printf.c —— CoreMark 端口自带的极简 printf
 *
 * 为什么不用 libc 的 printf：
 *   1) newlib-nano 默认不实现 %f；加 -u _printf_float 后 .text 涨到 40680 字节，
 *      比 32KB 的 IROM 多出 7912 字节，链接直接失败（region IROM overflowed）。
 *   2) CoreMark 实际只用到 %s %d %u %lu %x / %04x / %f 这几种，
 *      自己写一份 ~0.5KB 就够，还顺带把 libc 的 stdio 缓冲整块省掉。
 *
 * 约定：core_portme.h 里 HAS_PRINTF=0 时，CoreMark 的 coremark.h 不再把
 *       ee_printf 定义成 printf，改由端口提供本函数（声明也在 core_portme.h）。
 *
 * 输出：magic UART 0xF000_0000，与 syscalls.c 同一个地址 ——
 *       仿真台 tb_myCPU 把它打到 stdout；上板时需要 perip_bridge 里加译码。
 */
#include "coremark.h" /* 会带进 core_portme.h：ee_u32 / HAS_PRINTF / ee_printf 声明 */
#include <stdarg.h>

#define MAGIC_UART (*(volatile unsigned char *)0xF0000000)
#define MAGIC_STAT (*(volatile unsigned int  *)0xF0000008) /* bit0 = 发送忙（板上 UART） */

static void putc_(char c)
{
    /* 这里是 CoreMark 报表真正的字符出口（HAS_PRINTF=0 时走本文件，不走 syscalls.c）。
     * 板上是真实 UART：9600 波特下一个字符要 87us，而 printf 每几十个周期就写一个
     * 字节，不做流控一定丢字符 —— 所以先等忙位。
     * 仿真台不译码 0xF000_0008（读回 0），这个循环直接过，仿真行为不变。 */
    while (MAGIC_STAT & 1u) { }
    MAGIC_UART = (unsigned char)c;
}

/* 无符号整数：base=10/16，width=最小位宽，zero_pad=补 0 还是补空格 */
static void put_u(unsigned long v, unsigned base, int width, int zero_pad, int upper)
{
    char        buf[32];
    int         n = 0;
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";

    if (v == 0)
    {
        buf[n++] = '0';
    }
    else
    {
        while (v)
        {
            buf[n++] = digits[v % (unsigned long)base];
            v /= (unsigned long)base;
        }
    }
    for (int i = n; i < width; i++)
        putc_(zero_pad ? '0' : ' ');
    while (n > 0)
        putc_(buf[--n]);
}

static void put_d(long v)
{
    if (v < 0)
    {
        putc_('-');
        /* 取绝对值时避开 LONG_MIN 的溢出 */
        put_u((unsigned long)(-(v + 1)) + 1UL, 10, 0, 0, 0);
    }
    else
    {
        put_u((unsigned long)v, 10, 0, 0, 0);
    }
}

/* %f：定点打印，FLOAT_PREC 位小数。
 * CoreMark 只拿它印"秒数"和"Iterations/Sec"（量级都远小于 4000），
 * 所以 v*1e6 一定落在 32 位无符号范围内 —— 不需要 64 位浮点转换，
 * 省掉一大块 libgcc 的 soft-float 代码。 */
#define FLOAT_PREC 6
static void put_f(double v)
{
    unsigned long scaled;

    if (v < 0)
    {
        putc_('-');
        v = -v;
    }
    if (v > 4000.0)
        v = 4000.0; /* 防溢出：正常跑不到这个量级 */
    scaled = (unsigned long)(v * 1000000.0 + 0.5); /* 四舍五入 */
    put_u(scaled / 1000000UL, 10, 0, 0, 0);
    putc_('.');
    put_u(scaled % 1000000UL, 10, FLOAT_PREC, 1, 0);
}

int ee_printf(const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    while (*fmt)
    {
        int zero = 0, width = 0;

        if (*fmt != '%')
        {
            putc_(*fmt++);
            continue;
        }
        fmt++; /* 跳过 '%' */

        if (*fmt == '0')
        {
            zero = 1;
            fmt++;
        }
        while (*fmt >= '0' && *fmt <= '9')
        {
            width = width * 10 + (*fmt - '0');
            fmt++;
        }
        if (*fmt == '.') /* 精度：%f 用固定精度，这里只跳过 */
        {
            fmt++;
            while (*fmt >= '0' && *fmt <= '9')
                fmt++;
        }
        while (*fmt == 'l' || *fmt == 'h')
            fmt++; /* %lu / %ld：RV32 上 long 就是 32 位，直接当 32 位读 */

        switch (*fmt)
        {
            case 's': {
                const char *s = va_arg(ap, const char *);
                if (!s)
                    s = "(null)";
                while (*s)
                    putc_(*s++);
                break;
            }
            case 'd':
                put_d((long)va_arg(ap, int));
                break;
            case 'u':
                put_u((unsigned long)va_arg(ap, unsigned int), 10, width, zero, 0);
                break;
            case 'x':
                put_u((unsigned long)va_arg(ap, unsigned int), 16, width, zero, 0);
                break;
            case 'X':
                put_u((unsigned long)va_arg(ap, unsigned int), 16, width, zero, 1);
                break;
            case 'f':
                put_f(va_arg(ap, double));
                break;
            case 'c':
                putc_((char)va_arg(ap, int));
                break;
            case '%':
                putc_('%');
                break;
            default: /* 不认识的格式符：原样吐出来，便于发现漏支持 */
                putc_('%');
                if (*fmt)
                    putc_(*fmt);
                break;
        }
        if (*fmt)
            fmt++;
    }
    va_end(ap);
    return 0;
}
