# See LICENSE for license details.
#*****************************************************************************
# divu.S
#-----------------------------------------------------------------------------
# Test divu instruction.
#-----------------------------------------------------------------------
# Helper macros
#-----------------------------------------------------------------------
# We use a macro hack to simpify code generation for various numbers
# of bubble cycles.
#-----------------------------------------------------------------------
# RV64UI MACROS
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Tests for instructions with immediate operand
#-----------------------------------------------------------------------
# RV32 P-extension register-pair immediate-op tests.
# rs1 pair = {x13, x12} (even base), rd pair = {x15, x14}.
# Both halves of result are checked; on mismatch we jump to the same fail
# label as TEST_CASE, so the reported testnum matches.
#-----------------------------------------------------------------------
# Tests for an instruction with register operands
#-----------------------------------------------------------------------
# P-extension vxsat helpers.
# vxsat is a sticky CSR (0x009): set to 1 whenever an instruction saturates,
# never auto-cleared. To verify it deterministically per test we clear it
# before the instruction and check the expected post-value after.
# Using the literal CSR address keeps these macros toolchain-independent.
#-----------------------------------------------------------------------
# Tests for an instruction with register-register operands
#-----------------------------------------------------------------------
# RV32 P-extension register-pair register-register tests.
# rs1 pair = {x13, x12} (even base), rd pair = {x15, x14}, rs2 = x11.
# Both halves of result are checked; on mismatch we jump to the same fail
# label as TEST_CASE, so the reported testnum matches.
#-----------------------------------------------------------------------
# Test memory instructions
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Test jump instructions
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# RV64UF MACROS
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Tests floating-point instructions
#-----------------------------------------------------------------------
# 16-bit half precision (float16)
# 32-bit single precision (float)
# 64-bit double precision (double)
#-----------------------------------------------------------------------
# Pass and fail code (assumes test num is in gp)
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Test data section
#-----------------------------------------------------------------------

.section .text.init,"ax"; .option norvc; .balign 4; .globl _start; _start: li s10, 0; li s11, 0; li gp, 0;
  #-------------------------------------------------------------
  # Arithmetic tests
  #-------------------------------------------------------------
  test_2: li gp, 2; li x11, ((20) & ((1 << (32 - 1) << 1) - 1)); li x12, ((6) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_3: li gp, 3; li x11, ((-20) & ((1 << (32 - 1) << 1) - 1)); li x12, ((6) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((715827879) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_4: li gp, 4; li x11, ((20) & ((1 << (32 - 1) << 1) - 1)); li x12, ((-6) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_5: li gp, 5; li x11, ((-20) & ((1 << (32 - 1) << 1) - 1)); li x12, ((-6) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_6: li gp, 6; li x11, ((-1<<31) & ((1 << (32 - 1) << 1) - 1)); li x12, ((1) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((-1<<31) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_7: li gp, 7; li x11, ((-1<<31) & ((1 << (32 - 1) << 1) - 1)); li x12, ((-1) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_8: li gp, 8; li x11, ((-1<<31) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((-1) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_9: li gp, 9; li x11, ((1) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((-1) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_10: li gp, 10; li x11, ((0) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0) & ((1 << (32 - 1) << 1) - 1)); divu x14, x11, x12;; li x7, ((-1) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  bne x0, gp, pass; fail: li s11, 0; li s10, 1; loop_fail: j loop_fail;; pass: li s11, 1; li s10, 1; loop_pass: j loop_pass;

  .data
.balign 4; .globl begin_signature; begin_signature:
 
.balign 4; .globl end_signature; end_signature:
