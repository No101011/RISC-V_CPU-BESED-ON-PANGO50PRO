# B1：Zba + O2 镜像包

生成日期：2026-10-11。工具链：xPack GCC 15.2.0。

相对 A1 的编译配置变更是 `-march=rv32im_zicsr` →
`-march=rv32im_zba_zicsr`。保持 `-O2`、`-mabi=ilp32`、`-mcmodel=medlow`、
newlib_nano，无 LTO。独立输出目录使报表中的 include/map 路径也相应变化。
全部官方核心源码及 coremark.h 的 LF 归一化哈希均与固定官方版本一致。

## 已生成文件

| 子目录 | 用途 | 运行模式 | 次数 | CPU_HZ |
|---|---|---|---:|---:|
| `performance` | 与原 A1 的 2200 次运行对照 | performance | 2200 | 83333333 |
| `performance_long` | 为满足至少 10 秒留出余量 | performance | 4000 | 83333333 |
| `validation` | 官方验证种子 | validation | 4000 | 83333333 |
| `sim_performance` | 短 RTL 仿真、性能诊断与 CRC 检查 | performance | 10 | 100000000 |
| `sim_validation` | 短 RTL 仿真、验证种子 CRC 检查 | validation | 10 | 100000000 |

每个目录包含两份 PDS DAT、ELF、HEX、map、反汇编、实际参数头文件、
构建日志、源码/镜像哈希 manifest 和 `zba_instructions.txt`。

构建结果：每组 `.text` 为 **19,508 字节 / 4,877 指令字**，低于 32 KB IROM。
既有 A1 官方 performance 包为 19,712 字节 / 4,928 指令字。
每组反汇编中均有 **51 个静态 Zba 指令位置**；这不是运行时执行次数。
ELF 与 HEX 已核对一致，计时 CSR PC 为 `80002660`、`8000266c`。

生成阶段只编译、打包和核对产物，没有运行 RTL 仿真、PDS 或上板测试。
后续用户已提供下述 B1 性能上板日志。工作区活动 DAT 经哈希核对仍为此前 A1 validation，
不能据此推断用户 PDS 中当前 IP 的初始化文件路径；生成本包没有选择或替换活动镜像。

## B1 性能上板结果（用户提供，2026-10-11）

原始日志：`performance/board_performance_2026-10-11.log`，由用户粘贴，非代理直接采集。
时间超过10秒，performance 的 seedcrc 和全部 CRC 与预期一致，输出成功提示。

| 指标 | A1 上板基线 | B1 上板结果 |
|---|---:|---:|
| 频率 / 次数 | 83333333 Hz / 2200 | 83333333 Hz / 2200 |
| Total ticks | 874274872 | 870744965 |
| 时间（秒） | 10.491299 | 10.448940 |
| CoreMark | 209.697589 | 210.547680 |
| CoreMark/MHz | 2.516371 | 2.526572 |
| 周期/迭代 | 397397.669091 | 395793.165909 |

B1 周期减少 3529907（0.403753%），每次迭代减少1604.503182周期，
吞吐量提高0.405389%。这是一次用户上板运行的比较；具体周期收益来源尚无
新计时区间仿真报表支持。B1 validation 种子运行仍待测试，本次未重新核对 PDS 时序。
原 ZIP 为生成阶段快照；后续测试记录以本目录和 manifest 为准。

## 上板测试

在仓库根目录执行以下命令，选择 2200 次性能镜像：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/select_coremark_image.ps1 -RunMode Performance -PackageDir fpga/pds/coremark_b1/performance
```

该脚本核对两份 DAT 的 SHA256、备份旧活动 DAT，然后成对更新
`fpga/pds/imem_coremark.dat`、`dmem_coremark.dat`。

随后在现有 PDS 工程中：

1. 重新生成 **irom_bram 和 bram_dram**，同步内联初始化内容。
2. Compile → Synthesize → Device Map → Place & Route → Generate Bitstream。
3. 核对 CPU `clkout1→clkout1` setup WNS、TNS 及 hold，再下载。
4. UART 使用 9600-8-N-1，文本接收，保存完整输出。

**若 2200 次运行不足 10 秒**，该次周期仍能用于性能分析，但不满足官方有效成绩规则。
改用准备好的 4000 次性能镜像，再执行相同 PDS 步骤：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/select_coremark_image.ps1 -RunMode Performance -PackageDir fpga/pds/coremark_b1/performance_long
```

验证种子镜像选择命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/select_coremark_image.ps1 -RunMode Validation -PackageDir fpga/pds/coremark_b1/validation
```

恢复 A1 验证镜像用原命令 `-RunMode Validation`，不传 `-PackageDir`；
恢复 A1 性能镜像用 `-RunMode Performance`，不传 `-PackageDir`。
每次选择后都须更新两个内存 IP 和 bitstream。

## 核对串口输出

| 模式 | seedcrc | crclist | crcmatrix | crcstate |
|---|---|---|---|---|
| performance | e9f5 | e714 | 1fd7 | 8e3a |
| validation | 18f2 | e3c1 | 0747 | 8d84 |

完整上板运行应达到至少 10 秒，显示 `Correct operation validated`，且没有 `ERROR!`。
验证模式通常不打印 `CoreMark 1.0` 成绩行。不要把不同次数的 `crcfinal` 当成统一常量。
检查 Compiler flags 确实包含 `rv32im_zba_zicsr`、`-O2`，且没有 `-flto`。
本端口低 32 位周期计时要求单次计时少于约 51.54 秒（83.333333 MHz）。

比较指标：`周期/迭代 = Total ticks / Iterations`；
`CoreMark/MHz = 1000000 × Iterations / Total ticks`（单上下文性能运行）。
A1 上板基线为 **397397.67 周期/迭代、2.51637 CoreMark/MHz**。
改变迭代次数时按每迭代周期比较，并留意短运行的启动/预测器预热影响。

## 短仿真测试

在仓库根目录启动以下命令：

```powershell
$env:LM_LICENSE_FILE = 'D:/realsoftwares/modelsim/LICENSE.TXT'
$env:MGLS_LICENSE_FILE = $env:LM_LICENSE_FILE
$env:COREMARK_IMEM_HEX = '../../fpga/pds/coremark_b1/sim_performance/imem.hex'
$env:COREMARK_DMEM_HEX = '../../fpga/pds/coremark_b1/sim_performance/dmem.hex'
$env:COREMARK_MAX_CYCLES = '20000000'
$env:COREMARK_REPORT_CSV = 'coremark_b1_performance.csv'
$env:COREMARK_PERF_ENABLE = '1'
Remove-Item Env:COREMARK_PERF_ELF -ErrorAction SilentlyContinue
Push-Location sim/programs
try {
    & 'D:/realsoftwares/modelsim/win64/vsim.exe' -c -do coremark.do
} finally {
    Pop-Location
}
```

如 Python 不在 PATH，用 `COREMARK_PYTHON` 指定可执行文件。
验证短仿真将上述两份 HEX 路径中的 `sim_performance` 换为 `sim_validation`，
CSV 名改为 `coremark_b1_validation.csv`。
先确认 `Total ticks cross-check: MATCH`，再分析 `COREMARK_TIMED` 中的
周期/迭代、架构指令数、融合次数和停顿分桶。
10 次仿真的不足 10 秒提示属于预期，不能作为官方上板成绩。

## 重新生成 B1

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/build_coremark_b1.ps1
```

可用 `-Toolchain` 指定工具链 bin 目录、`-Python` 指定 Python 可执行文件。
构建只写 `tests/coremark/build/b1/` 与本镜像包目录，保留 A1 构建及官方镜像包。
生成脚本不会自动选择活动 DAT。
