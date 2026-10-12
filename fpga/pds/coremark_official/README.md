> 2026-10-12：用户决定仅采用B2，本目录DAT已删除；源码、ELF、历史日志及参数记录保留。当前镜像见 ../coremark_b2/。

# CoreMark 官方性能与验证运行

两组镜像使用同一套核心源码、优化、架构、ABI 和内存配置。仅切换官方运行宏、种子与迭代次数。
六个官方源码文件在导出镜像时检查 LF 归一化后的哈希；官方固定版本为
[1f483d5b](https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777)。

| 模式 | 种子 | 迭代次数 | CPU_HZ | seedcrc | list / matrix / state CRC |
|---|---|---:|---:|---|---|
| performance | 0,0,0x66 | 2200 | 83333333 | e9f5 | e714 / 1fd7 / 8e3a |
| validation | 0x3415,0x3415,0x66 | 4000 | 83333333 | 18f2 | e3c1 / 0747 / 8d84 |

## 已有证据与运行状态

- 用户提供的最近性能运行记录在 `../coremark_board_2026-10-10_full_params.log`：
  2200 次、10.491299 秒、209.697589 CoreMark、三个 CRC 通过。
- 本目录的 performance 和 validation 都是新编译的独立镜像；每组含两份 DAT、ELF、
  参数头文件和 `build_manifest.json`。各 manifest 记录编译配置、源码和镜像哈希。
- validation 已完成10次 RTL 仿真，三个 CRC 符合表中预期；3969339 ticks。
  原始日志在 `validation/simulation_crc_10iters.log`。0.039693秒的短仿真会输出不足10秒错误及
  `Errors detected`，因此该记录只用于CRC检查，不能替代完整官方运行。
  4000次在83.333MHz下估计约19.05秒，须以上板实际时间为准。
- 用户现已提供真实板卡 validation 日志，保存在 `validation/board_validation.log`：
  4000次、1588608811 ticks、19.063306秒，seedcrc=18f2、三个CRC=e3c1/0747/8d84、crcfinal=5249，
  输出 `Correct operation validated`，没有 `ERROR!`。
  已与性能基线一起补齐官方开源规则要求的两组运行证据；日志由用户提供，非代理直接采集。
- 报告的性能成绩引用实际 performance 结果 **209.697589 CoreMark、约2.51637 CoreMark/MHz**。
  validation 的 Iterations/Sec=209.827196 仅为该组运行吞吐量，不取代性能成绩。
- 若要证明新 performance 包的硬件结果，亦需运行该包并保存日志；已有串口日志来自此前已验证的镜像。
- validation 成功后没有 `CoreMark 1.0` 成绩行，这是官方 main 的正常行为；成绩使用 performance 运行。
- 当前 32 位周期计时器要求单次计时小于约 51.54 秒；检查板上实际时间。
- 本工作按官方开源运行规则准备，不等同于 EEMBC 机构认证或提交审核。

官方运行规则：[README / Run Rules](https://github.com/eembc/coremark/blob/1f483d5b8316753a742cbf5590caf5bd0a4e4777/README.md#run-rules)。

## 切换为验证镜像并上板

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/select_coremark_image.ps1 -RunMode Validation
```

该脚本检查两份 DAT 的 SHA256，备份原活动 DAT，然后一起更新
`fpga/pds/imem_coremark.dat` 和 `fpga/pds/dmem_coremark.dat`。

**已执行该选择操作，活动 DAT 当前为 validation；用户随后已完成该镜像的上板验证。**
切换前的两份 DAT 备份于 `../_backup_coremark_selection_20261010_234629_762/`。

以后重新构建或切换镜像，接着在 PDS 中：

1. 重新生成 **irom_bram 和 bram_dram** 两个 IP，让内联初始化参数同步更新。
2. Compile → Synthesize → Device Map → Place & Route → Generate Bitstream。
3. 下载并等待完整 UART 文本，保存为 validation 的真实板卡日志。
4. 核对表中的类型、seedcrc、三个 CRC、时间范围和成功提示。

切回新性能镜像使用相同脚本的 `-RunMode Performance`，再执行相同 PDS 步骤。
选择镜像只更新 DAT，不能自动更新 IP、bitstream 或 FPGA。

## 重建两组镜像

PowerShell（仓库根目录；工具链路径按本机配置）：

```powershell
powershell -File tests/coremark/build.ps1 -Toolchain D:/realsoftwares/xpack-riscv-none-elf-gcc-15.2.0-1/bin -RunMode Performance -Iters 2200 -CpuHz 83333333 -BuildDir build/official/performance
powershell -File tests/coremark/build.ps1 -Toolchain D:/realsoftwares/xpack-riscv-none-elf-gcc-15.2.0-1/bin -RunMode Validation -Iters 4000 -CpuHz 83333333 -BuildDir build/official/validation
python tests/coremark/scripts/export_pds_image.py --build-dir tests/coremark/build/official/performance --output-dir fpga/pds/coremark_official/performance
python tests/coremark/scripts/export_pds_image.py --build-dir tests/coremark/build/official/validation --output-dir fpga/pds/coremark_official/validation
```

Makefile（在 tests/coremark 目录）：

```sh
make RUN_MODE=performance BUILD=build/official/performance ITERS=2200 CPU_HZ=83333333 LIBC=newlib_nano
make RUN_MODE=validation BUILD=build/official/validation ITERS=4000 CPU_HZ=83333333 LIBC=newlib_nano
```

Makefile 和 PowerShell 均支持两种模式；固定 2000 字节总缓冲区，并为全部源文件传递同一组编译参数。
只有一种运行模式可被选择，非法模式或同时开启两种模式会报错。
