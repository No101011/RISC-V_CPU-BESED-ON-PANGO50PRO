# B2：Zba + O3，直接与 B1 对比

生成日期：2026-10-11；xPack GCC 15.2.0。
编译参数为 `-march=rv32im_zba_zicsr -mabi=ilp32 -mcmodel=medlow -O3`，
无 LTO，使用 newlib_nano。相对 B1 的优化参数只从 `-O2` 改为 `-O3`；
独立输出目录使参数报表中的 include/map 路径相应变化。
官方核心源码、CPU RTL、时钟和内存配置保持原配置。

## 推荐先测 4000 次性能版

为减少因不足10秒而再次重建 PDS 的机会，直接使用 `performance_long`。
它与 2200 次版本采用相同优化参数和 performance 种子，按每迭代周期比较。

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/select_coremark_image.ps1 -RunMode Performance -PackageDir fpga/pds/coremark_b2/performance_long
```

脚本先核对两份 DAT 的 SHA256、备份原活动 DAT，再成对选择新镜像。
接着在 PDS 中：

1. 重新生成 **irom_bram 和 bram_dram**，确保初始化同步。
2. Compile → Synthesize → Device Map → Place & Route → Generate Bitstream。
3. 核对 CPU setup/hold，再下载；UART 使用 9600-8-N-1 文本接收。
4. 保存完整报表，确认 `-O3`、`rv32im_zba_zicsr`、CPU_HZ=83333333、Iterations=4000。

若要同为2200次的对照，把 PackageDir 改为 `fpga/pds/coremark_b2/performance`。
其运行时间可能不足10秒：仍可分析周期/迭代，但不满足有效成绩的时间要求。
4000次是否达到10秒同样以实际串口时间为准。

## 五套独立文件

| 目录 | 模式 | 次数 | CPU_HZ |
|---|---|---:|---:|
| `performance` | performance | 2200 | 83333333 |
| `performance_long` | performance | 4000 | 83333333 |
| `validation` | validation | 4000 | 83333333 |
| `sim_performance` | performance | 10 | 100000000 |
| `sim_validation` | validation | 10 | 100000000 |

每组包含 DAT、ELF、HEX、map、反汇编、实际参数头文件、构建日志、源码/镜像哈希
manifest 和静态 Zba 指令清单。全部 `.text` 为 **21836字节 / 5459字**，
能放入32KB IROM；比 B1 的19508字节增加2328字节。
反汇编中有43个静态Zba位置，此数量不能用于直接预测性能。
全部官方核心源码哈希及 ELF/HEX 一致性已核对，计时 CSR PC 为
`80002c00`、`80002c0c`。

生成过程只编译和打包，代理未运行 B2 仿真、PDS 或上板测试，也未选择活动 DAT。
用户随后提供了 performance_long 上板日志，结果如下；其他包仍未提供运行记录。

## 2026-10-11 上板结果

证据为用户粘贴的串口文本，保存在
`performance_long/board_performance_2026-10-11.log`，非代理直接采集。
4000 次、1583923553 ticks、19.007083 秒，seedcrc=e9f5，
CRC=e714/1fd7/8e3a，crcfinal=65c5，显示 `Correct operation validated`。
本次性能运行时间与 CRC 要求通过；B2 validation 种子运行仍待记录，未重新核对 PDS 时序。

| 配置 | 次数 | CoreMark | CoreMark/MHz | 周期/迭代 | .text 字节 |
|---|---:|---:|---:|---:|---:|
| A1：RV32IM+Zicsr、O2 | 2200 | 209.697589 | 2.516371 | 397397.669091 | 19712 |
| B1：增加 Zba、O2 | 2200 | 210.547680 | 2.526572 | 395793.165909 | 19508 |
| B2：Zba、O3 | 4000 | 210.447866 | 2.525374 | 395980.888250 | 21836 |

同为83333333Hz，B2 相比 B1 每迭代增加187.722341周期，吞吐量低0.047407%；
相比 A1 吞吐量高0.357790%。B2 .text 比 B1 多2328字节（11.933566%）。
当前结果没有显示 O3 的性能收益，优先保留 B1 O2 作为候选。
两次迭代次数不同且差异很小，不能据此确定具体优化造成了回退；
如需严格确认排序，应使用相同次数比较，并查看计时窗口的动态统计。
crcfinal 随迭代次数变化，此处65c5与2200次的33ff不同并不表示失败。
原 ZIP 是生成时快照；后续上板记录以本目录和 manifest 为准。

## 比较基线

用户已经提供的 B1 上板性能结果：

- 83333333Hz、2200次、870744965 ticks。
- 210.547680 CoreMark，2.526572 CoreMark/MHz。
- **395793.165909 周期/迭代**。
- 日志在 `../coremark_b1/performance/board_performance_2026-10-11.log`。

计算 `B2周期/迭代 = B2 Total ticks / B2 Iterations`，与上述 B1 比较。
同频率下吞吐量收益为 `B1周期/迭代 / B2周期/迭代 - 1`。
不同次数的 Total ticks 总数不能直接比较，预热的影响也应留意。

performance 预期 seedcrc=e9f5、CRC=e714/1fd7/8e3a。
运行至少10秒并显示 `Correct operation validated` 才符合该性能运行的时间/CRC要求。
`crcfinal` 随次数变化，不要要求4000次也等于此前2200次的33ff。
本轮可先比较性能；确定候选配置后再补 validation 种子记录。

validation 选择命令使用 `-RunMode Validation -PackageDir fpga/pds/coremark_b2/validation`。
其预期 seedcrc=18f2、CRC=e3c1/0747/8d84，正常不打印 `CoreMark 1.0` 成绩行。

恢复 B1 性能版使用 `-RunMode Performance -PackageDir fpga/pds/coremark_b1/performance`。
不传 PackageDir 则选择原 A1 官方包。每次选择后均须更新两个内存IP和bitstream。

## 短仿真及重建

在 `sim/programs` 运行 `coremark.do` 前，设置：

```powershell
$env:COREMARK_IMEM_HEX = '../../fpga/pds/coremark_b2/sim_performance/imem.hex'
$env:COREMARK_DMEM_HEX = '../../fpga/pds/coremark_b2/sim_performance/dmem.hex'
$env:COREMARK_REPORT_CSV = 'coremark_b2_performance.csv'
$env:COREMARK_MAX_CYCLES = '20000000'
$env:COREMARK_PERF_ENABLE = '1'
Remove-Item Env:COREMARK_PERF_ELF -ErrorAction SilentlyContinue
& 'D:/realsoftwares/modelsim/win64/vsim.exe' -c -do coremark.do
```

验证短仿真把两份 HEX 路径中的 `sim_performance` 改为 `sim_validation`。
ModelSim 的许可证环境沿用原配置。Python 不在 PATH 时设置 COREMARK_PYTHON。
短仿真不足10秒属于预期，先核对 CRC 和 `Total ticks cross-check: MATCH`。

在仓库根目录重建全部 B2 文件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/build_coremark_b2.ps1
```

可指定 `-Toolchain`、`-Python`。产物在 `tests/coremark/build/b2/` 和本目录。
通用 `tests/coremark/build.ps1` 新增 `-Optimization O2|O3`，默认仍为 O2，
原 A1/B1 构建命令保持有效；官方核心源码未修改。
