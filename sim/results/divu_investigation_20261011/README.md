# DIVU testnum=8 失败原因调查

日期：2026-10-11。此次为静态调查：读取已有仿真日志、解码本地测试镜像、核对 RTL 与官方规范/测试源码。
未修改 RTL、测试镜像或活动 DAT，未运行新的仿真/回归。

## 已确认的问题

本地 `tests/unofficial_test_data/rv32um-p-divu.dat`（与同名 `.txt` 字节完全相同）
将 testnum=8、9、10 的 DIVU 除零预期值错误地设置为 `0x80000000`。
RISC-V RV32 的正确除零商为 `0xFFFFFFFF`，与被除数无关。
因此原日志中的这一 FAIL 不能作为 DIVU RTL 缺陷的证据。

| testnum | 被除数 x1 | 除数 x2 | 本地预期 x29 | 正确预期 | 错误加载指令行号 / PC |
|---|---|---|---|---|---|
| 8 | 0x80000000 | 0 | 0x80000000 | 0xFFFFFFFF | 43 / 0x800000a8 |
| 9 | 1 | 0 | 0x80000000 | 0xFFFFFFFF | 49 / 0x800000c0 |
| 10 | 0 | 0 | 0x80000000 | 0xFFFFFFFF | 55 / 0x800000d8 |

testnum=8 镜像对应的汇编为：

```asm
# PC          machine word
# 8000009c    800000b7
lui  x1, 0x80000       # 被除数 = 0x80000000
# 800000a0    00000113
addi x2, x0, 0         # 除数 = 0
# 800000a4    0220df33
divu x30, x1, x2
# 800000a8    80000eb7
lui  x29, 0x80000      # 错误预期 = 0x80000000
# 800000ac    00800193
addi x3, x0, 8
# 800000b0    03df1c63
bne  x30, x29, fail
```

符合规范的 CPU 返回全1时，会被该镜像判为失败；测试在第8项结束，第9/10项尚未覆盖。
不能把 `0x80000000 / 0` 混同于有符号 `0x80000000 / 0xFFFFFFFF` 的溢出情况。

## RTL 与已有日志

`rtl/core/ctrl.v` 将 funct3=101 解码为 ALU_DIVU。
`rtl/core/mdu.v:79` 捕获除零标志；`:111` 的结果分支对 DIV/DIVU 返回全1，对 REM/REMU 返回被除数：

```verilog
if (div_by_zero_r) begin
    result <= div_need_rem_r ? div_dividend_r : 32'hFFFF_FFFF;
end
```

该特殊情况绕过32轮正常除法迭代，现有逻辑符合规范。
现有 `sim/results/btb_2bit_tag_20261011_194410/riscv_tests.log` 为46 PASS、1 FAIL、0 HANG；
旧BTB备份的 `baseline_divu.log` 同样testnum=8、476周期失败，说明此报告在BTB修改前已存在。
这些日志未记录失败时的x30实际值，本次没有重新获取动态写回轨迹；
可以确认测试基准错误，不能据静态调查声称所有DIVU执行/转发路径已动态验证。

`sim/run_riscv.sh:42` 早已注明除零预期问题，并跳过该镜像。
其“官方参考数据”措辞应理解为本地导入的镜像；当前官方 `divu.S` 的三项预期均正确设为-1。
关键词检索历史精简记录也找到同一问题；本次未追溯本地镜像生成器或错误引入提交。

## 官方依据

- [RISC-V M 扩展：Division Operations](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)：除零商为全1，余数为被除数；无符号除法不存在有符号溢出特例。
- [官方 riscv-tests RV32 DIVU 源码](https://github.com/riscv-software-src/riscv-tests/blob/master/isa/rv32um/divu.S)：testnum=8/9/10 的预期商均为-1（RV32即0xFFFFFFFF）。

## 修正建议与记录口径

正确加载预期值应使用 `addi x29,x0,-1`，机器码 `fff00e93`。
若后续修复此镜像，应先备份，再将 `.dat` 与 `.txt` 的第43、49、55行
从 `80000eb7` 改为 `fff00e93`，只改变预期值，不改DIVU、操作数或跳转偏移。
该替换保持每条指令4字节，其他指令位置不变。更完整的办法是从固定版本官方源码重建测试。

随后需要运行纠正后的DIVU用例及完整回归，才能记录47 PASS。
当前记录应为：**原始结果46 PASS、1 FAIL、0 HANG；DIVU镜像除零预期无效，纠正后的回归待运行**。
不应继续将这项失败列为已证实的除法器缺陷，也不应直接改记为47 PASS。

后续用户授权替换后，已从官方divu.S及测试宏编译并替换本地.dat/.txt/.dump，
官方源码和宏保持不变，仅适配项目结束标志。原错误文件保存在
`tests/unofficial_test_data/_backup_pre_official_divu_20261011_205151_365291/`。
本文前面的旧指令/行号/哈希指该备份，当前活动镜像已不同。
详情见 `tests/official_riscv_divu_20261011/README.md`；新RTL回归尚未运行。

## 输入 SHA256

### 后续：镜像来源与 CoreMark 构建关系

用户追问预期错误是否由CoreMark源码或编译引起，进一步核对结果：

- DIVU指令回归直接加载 `tests/unofficial_test_data/rv32um-p-divu.dat`；CoreMark构建脚本只编译 `tests/coremark/src` 和 `port`，不读取/生成这个DIVU镜像，属于两条独立流程。
- 本地 `rv32um-p-divu.dump` 的a8/c0/d8偏移也已经包含错误的80000eb7。其64条完整32位指令与.dat逐项一致。因此错误已存在于所保存的反汇编对应机器码，不是只在当前.dat加载或字节序处理时出现。
- Git中该.dat的三处错误在首次提交98f4280（2026-10-11 17:21:32 +0800）已存在，没有更早的版本历史；.dump未纳入Git。
- 本地没有找到DIVU对应原始.S、测试宏、生成脚本或原始ELF，因而不能进一步确定是旧测试源码/宏修改、旧汇编生成问题，还是导入前编辑。不能据此断言GCC编译器有bug。
- 当前CoreMark五个核心C文件及coremark.h按CRLF转LF计算的MD5全部与固定官方版本manifest一致；已核对构建流程与官方core_main.c的CRC预期。它与DIVU镜像的错误没有直接关系。

综上，已确认的是**旧DIVU回归测试产物包含错误预期**；错误最早如何进入该产物，因缺少原始构建输入仍无法确定。

```text
rv32um-p-divu.dat / .txt
9ac36419ecd710cd59814e2008050c9c822683946b0eb457d1a053880fdb085d
rtl/core/mdu.v
826597ba3495b3014ad6f8943fa378143352bfdb51751a719ef4597798baed3b
rtl/soc/myCPU.sv
db8750e0b7772cc7296e3c3e3e772f09bf030fe1265358e451854a9d4ec608cb
```
