# 官方 DIVU 源码重建与本地错误镜像替换

日期：2026-10-11，按用户要求替换错误测试代码。

## 来源与适配

官方仓库：https://github.com/riscv-software-src/riscv-tests。
通过官方codeload HEAD ZIP获取，Git archive注释的提交为
`7b68f7b91f827f8d94cc1c57ff123752c5c8f704`。
下载压缩包和文件哈希在 `upstream_provenance.json`。

直接使用官方 `isa/rv32um/divu.S` 及 `isa/macros/scalar/test_macros.h`，两者内容未改。
官方testnum=2至10全部保留，第8/9/10项除零的预期商均为-1（0xFFFFFFFF）。

`env/riscv_test.h` 是项目仿真环境适配：x26表示结束，x27表示通过，x3保存testnum，
与tb_myCPU/tb_riscv一致。省略本例不需要的特权启动及tohost机制。
`env/link.ld` 将代码链接到CPU复位地址0x80000000。
官方宏使用x11/x12作为操作数、x14作为结果、x7作为预期值；新镜像的寄存器与指令顺序
遵循官方宏，因此不局限于对旧镜像三行进行手工修改。

## 已完成

- GCC 15.2.0，RV32IM/ILP32，编译与链接退出码0，无错误/警告诊断。
- 生成代码260字节（65条32位指令），DAT/TXT均保留98字深度，尾部补0，无BOM。
- 静态解码核对全部9项的输入、预期常量、DIVU指令与比较寄存器，全部吻合。
- 第8/9/10项机器码中加载预期值的指令均为 `fff00393`，即 `addi x7,x0,-1`。
- 安装前完整备份原.dat/.txt/.dump并核对SHA256。
- 替换 `tests/unofficial_test_data/rv32um-p-divu.dat`、`.txt`、`.dump`；
  新增同目录 `.S`，与官方divu.S字节一致，便于追踪来源。
- 原ModelSim `sim/programs/riscv_tests.do` 自动读取此路径，无需改动。
- `sim/run_riscv.sh` 恢复DIVU参与回归，并将汇总用例数改为实际统计值。

备份目录：`tests/unofficial_test_data/_backup_pre_official_divu_20261011_205151_365291/`。
新DAT/TXT SHA256：`ac4c1d80f021c87a15799a17e576829624dbe2e585d199ee7d68f24a9643609d`。
完整编译命令、预处理汇编、ELF/BIN、反汇编在 `build/`，结果及SHA256在 `build_manifest.json`。

## 重建

在仓库根目录执行（Python需在PATH，或使用本机Python绝对路径）：

```powershell
python tests/official_riscv_divu_20261011/rebuild.py
```

只生成build文件。加 `--install` 会先备份再安装新的.dat/.txt/.dump/.S。
脚本先校验官方源码哈希，再编译并检查全部测试项编码，检查完成后才安装。

## 验证范围

本次完成编译、机器码常量检查及文件替换，未运行RTL仿真/完整指令回归。
当前不能宣布DIVU运行PASS或47 PASS；原始46 PASS/1 FAIL日志作为历史记录保留。
新镜像已可供现有ModelSim回归加载。CPU RTL、CoreMark和上板活动DAT没有因本次替换改变。
