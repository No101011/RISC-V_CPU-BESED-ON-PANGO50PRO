# B2：Zba + O3，直接与 B1 对比

## 最终采用配置（2026-10-11）

用户已决定采用 **B2：rv32im_zba_zicsr、O3、无LTO**，结束B3/B4后续对比。
当前正式基线为新BTB下的237.628390 CoreMark、2.851541 CoreMark/MHz。
性能和验证模式的既有上板记录均已通过，详见后文。

两份根目录活动DAT已备份并成对选择本包的`performance_long/`（4000次、83333333Hz）。
PDS工程两个内存IP的.idf INIT_FILE已备份并切回本包同目录的对应DAT绝对路径。
配置记录见`../adopted_coremark_config.json`。
此操作仅更新输入配置，未重生成IP或位流；下次下载前重新加载IP配置并生成两个内存IP及位流。
B3/B4产物和已有validation日志保留，不再主动推进后续对比。

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
用户随后提供了 performance_long 和新BTB validation 上板日志，结果如下；其他包仍未提供运行记录。

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
上述修改前硬件结果没有显示 O3 的性能收益，当时优先保留 B1 O2 作为候选。
两次迭代次数不同且差异很小，不能据此确定具体优化造成了回退；
如需严格确认排序，应使用相同次数比较，并查看计时窗口的动态统计。
crcfinal 随迭代次数变化，此处65c5与2200次的33ff不同并不表示失败。
原 ZIP 是生成时快照；后续上板记录以本目录和 manifest 为准。

## 同日后续：新 BTB 上板结果

用户在BTB改为两位方向计数器+PC[14]标签后提供新串口日志：
`performance_long/board_performance_btb_2bit_tag_2026-10-11.log`。
旧日志保留，两次报表都是B2 Zba+O3、4000次、CPU_HZ=83333333，参数路径一致。
新报表为1402750453 ticks、16.833006秒、237.628390 CoreMark，
seedcrc=e9f5、CRC=e714/1fd7/8e3a、crcfinal=65c5，显示Correct operation validated。
证据为用户粘贴的UART文本；没有独立核对下载镜像哈希或新PDS时序报告。

| 指标 | 旧BTB + B2 | 新BTB + B2 |
|---|---:|---:|
| 迭代次数 | 4000 | 4000 |
| 计时周期 | 1583923553 | 1402750453 |
| 时间（秒） | 19.007083 | 16.833006 |
| CoreMark | 210.447866 | 237.628390 |
| CoreMark/MHz | 2.525374 | 2.851541 |
| 周期/迭代 | 395980.888250 | 350687.613250 |

节省181173100周期，周期减少11.438248%，吞吐量提高12.915562%。
每迭代减少45293.275周期，成绩与给定CPU_HZ及ticks的计算一致。
本次performance时间和CRC要求通过；随后B2+新BTB的validation上板记录也已补齐，见下文。
此前11.198955%的短仿真收益使用B1 O2、10次，两者不是同一软件/迭代配置。
不能用新BTB+B2与旧BTB+B1的成绩比较来证明O3优于O2；
若继续比较优化级别，应在新BTB下使用B1 performance_long与本次结果比较。
本次只有UART结果，不能从中推算分支准确率、CPI或新实现的WNS/DRM。

随后用户生成PDS时序报告，已核对2026-10-11 19:41:59的新BTB实现：
All Constraints Met，CPU slow setup WNS=+0.935ns，全局最小setup=+0.253ns、hold=+0.082ns，
DRM=48.5/85（57.06%），最终P&R LUT=6929、FF=3040；综合映射确认两组2048×19bit BTB使用LUTRAM。
CPU关键路径为PC→BTB→下一PC选择，布线占80.57%；UART/LED外部I/O时序未约束提示仍存在。
完整分析和原始报告快照见 `../timing_btb_2026-10-11/README.md`，下载镜像哈希未独立核对。

## 同日后续：新 BTB + B2 validation 上板通过

用户提供的串口日志保存为 `validation/board_validation_btb_2bit_tag_2026-10-11_raw.log`。
移除三个接收软件时间戳并连接被分段的字段，整理版为
`validation/board_validation_btb_2bit_tag_2026-10-11.log`；未修改数值或编译参数。

4000次、1408802359 ticks、16.905628秒、236.607591 Iterations/Sec，CPU_HZ=83333333。
编译参数为Zba+Zicsr、O3、TOTAL_DATA_SIZE=2000、VALIDATION_RUN=1，与validation构建manifest一致。
本地官方core_main.c的2K validation预期为seedcrc=18f2、list/matrix/state=e3c1/0747/8d84，全部匹配。
crcfinal=5249也与此前4000次validation结果一致；程序显示Correct operation validated。

计时换算1408802359/83333333=16.9056283756秒，4000/该时间=236.6075907458次/秒，
与报表六位小数一致；每迭代352200.589750周期。
同一新BTB下，validation比performance多6051906周期（0.431431%），但两种模式使用不同种子，
数据会改变分支/运算行为，不能用validation的迭代率替代performance成绩。
validation不打印CoreMark 1.0成绩行是官方core_main.c只对performance known_id=3打印的正常行为。
CoreMark Size=666表示三个算法各自的数据大小，2000字节整数分配后每份666，并非测试规模设置错误。

新BTB+B2两种模式的上板时间与CRC检查现已通过。对外性能记录采用
**237.628390 CoreMark、2.851541 CoreMark/MHz**，validation迭代率作为验证信息保留。
证据仍为用户UART文本，下载镜像哈希未独立核对；CoreMark通过不等于全部ISA用例通过，
既有DIVU testnum=8原始失败记录保留。后续调查已确认本地测试镜像的除零预期错误，
该FAIL不能作为已证实RTL缺陷，纠正后的回归尚未运行；详见 `../../../sim/results/divu_investigation_20261011/README.md`。
原ZIP为生成时快照，最新记录在目录与manifest中。

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
