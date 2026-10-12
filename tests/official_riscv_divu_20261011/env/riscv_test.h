/* Project testbench adapter: x26=finished, x27=pass, x3=test number.
 * Upstream divu.S and test_macros.h are used without edits.
 * This arithmetic test needs no privileged initialization or tohost driver.
 */
#ifndef PROJECT_DIVU_RISCV_TEST_H
#define PROJECT_DIVU_RISCV_TEST_H

#define TESTNUM gp
#define RVTEST_RV32U
#define RVTEST_CODE_BEGIN \
    .section .text.init,"ax"; \
    .option norvc; \
    .balign 4; \
    .globl _start; \
_start: \
    li s10, 0; \
    li s11, 0; \
    li TESTNUM, 0;
#define RVTEST_CODE_END
#define RVTEST_PASS \
    li s11, 1; \
    li s10, 1; \
loop_pass: \
    j loop_pass;
#define RVTEST_FAIL \
    li s11, 0; \
    li s10, 1; \
loop_fail: \
    j loop_fail;
#define RVTEST_DATA_BEGIN \
    .balign 4; \
    .globl begin_signature; \
begin_signature:
#define RVTEST_DATA_END \
    .balign 4; \
    .globl end_signature; \
end_signature:

#endif
