# B2：最终采用 Zba + O3，无 LTO

## 2026-10-12：当前RTL热点仿真

用户授权的一次performance 10次@TB100MHz仿真完成：正常EXIT、CRC正确、UART/窗口3328865 ticks MATCH，
CPI_arch=1.146369299，归一化估计3.004026898/MHz，不替代上板正式成绩。
与两项load优化前相比少178623周期，EX2 load等待降为0；剩余EX1 load等待142508（4.281%），MUL等待129600（3.893%）。
分支/jump误预测计数未变；热点已按PC/函数整理。没有修改RTL或软件镜像，也没有实施四条待处理时序策略。
详细报告：[当前RTL热点统计](../../../sim/results/b2_mem1_hotspots_20261012_211042/README.md)。
当前validation与ISA回归仍待完成；短仿真不足10秒提示是预期的时长检查。

## 2026-10-12：普通 load MEM1 实时转发后 performance 上板通过

用户UART记录：`performance_long/board_performance_mem1_bram_fwd_2026-10-12.log`；计算结果见同名`_result.json`。
B2参数与本地manifest一致：Zba+O3、无LTO、4000次、83333333Hz。
seedcrc=e9f5，CRC=e714/1fd7/8e3a，final=65c5，Correct operation validated。
1331289264/83333333=15.975471232秒，得分250.383850463，均与串口四舍五入一致且超过10秒。
最新性能为**250.383850 CoreMark、3.004606 CoreMark/MHz**，332822.316周期/迭代。
相比上一版EX2 L0的1379802185 ticks，减少48512921周期，周期降低3.515933%，吞吐提升3.644056%。
相对新BTB、EX2 L0改动前的1402750453 ticks，累计吞吐提升5.367818%。
收益超过只估算两处LH/LBU→branch热点的约1.7%：本次路径覆盖所有符合条件的普通DRAM load，
该估计不是整个路径的上限。具体各PC/指令类型贡献尚需当前RTL热点统计，不能仅凭总ticks确定。
当前源文件SHA256=825a7158b3eaf00e546f86ff4b22491ade322cb8a56d624ff9ca3000c797783e，
仅记录本地源码状态，下载位流/镜像对应关系未独立核对。
新RTL的B2 validation及ISA回归仍待完成。随后19:30:55 PDS多corner报告已核对：All Constraints Met，
CPU setup +0.179ns、fast hold +0.067ns、DRM49/85，新增返回路径已成为关键路径，余量较小。
报告快照与完整分析见`../timing_mem1_bram_fwd_2026-10-12/README.md`；下载位流哈希仍未独立核对。
本次仅记录与分析用户日志，没有修改RTL/镜像/IP/FDC或运行仿真/实现。

## 非 B2 文件清理状态

2026-10-12：已先删除554个可重建的非B2产物。用户随后明确确认删除剩余旧备份、ZIP、审计和历史资料，
已完成剩余61个目标的清理（333个文件）。B1/B3/B4、旧A1、fresh/reclone副本及旧CoreMark对照记录已删除。
默认构建和仿真入口均采用B2；B2镜像、共享官方源码/BSP、CPU RTL及ISA回归用例保持不变。
清单和保护哈希见../b2_refresh_20261012_163627/non_b2_cleanup_plan.json。

## 2026-10-12：EX2 L0 查询后 B2 performance 上板通过

用户UART日志保存于`performance_long/board_performance_ex2_l0_2026-10-12.log`。
参数与当前B2 performance_long manifest一致：Zba+O3、无LTO、4000次、83333333Hz、performance种子。
seedcrc=e9f5、list/matrix/state=e714/1fd7/8e3a、final=65c5，Correct operation validated。
1379802185/83333333=16.557626286秒，迭代率241.580521921，与输出四舍五入一致，超过10秒。
本轮有效性能结果为**241.580522 CoreMark、2.898966 CoreMark/MHz**。

| 指标 | 新BTB、改动前B2 | EX2 L0查询后B2 |
|---|---:|---:|
| 周期 | 1402750453 | 1379802185 |
| 时间（秒） | 16.833006 | 16.557626 |
| CoreMark | 237.628390 | 241.580522 |
| CoreMark/MHz | 2.851541 | 2.898966 |
| 周期/迭代 | 350687.613250 | 344950.546250 |

同模式、编译参数、次数和频率比较，节省22948268周期，周期降低1.635948%、吞吐提升1.663156%。
此前B2 10次影子统计仅LW可省57343周期，理想吞吐提升1.662046%，与本轮实测收益接近。
按4000次线性外推预计省22937200周期，实测多省11068周期；短仿真和上板长运行有启动/热身差异，
不能把差值解释为每次命中的严格周期对账。软件DAT已确认与前次B2相同，结果支持EX2 L0优化的约1.66%收益。

证据为用户UART文本，下载位流/镜像哈希未独立核对，本轮PDS资源与时序也尚未核对。
当前新RTL+B2 validation结果仍待提供；旧BTB后B2 validation及新RTL+B4 validation记录分别保留。
本次只记录和分析结果，没有修改RTL、镜像、IP或执行新仿真/实现。

## 2026-10-12：重新编译与 DAT 清理

已重新编译4000次上板performance_long/validation及两组10次短仿真镜像，GCC15.2.0、O3、无LTO。
官方六个核心文件哈希通过，ELF/HEX匹配，DAT为无BOM纯LF、ROM8192行/RAM32768行。
根目录活动DAT已成对选择performance_long；当前PDS的ROM/RAM初始化常量均逐字匹配该包。
RAM通过调用PDS随附的原始Tcl初始化生成器更新，包装文件INIT_FILE也已同步；端口和IP架构未改变。
CPU RTL未因本次操作修改，没有运行仿真、PDS实现或下载；下一步从Compile重新生成位流。

删除50个旧/重复CoreMark DAT，包括B1/B3/B4、旧A1、重复导出/备份、B2旧2200次DAT及旧B4解码DAT。
旧压缩包中40个DAT条目也已移除；源码、ELF/HEX、历史日志和参数记录保留，ISA回归DAT不变。
当前完整包为`../coremark_b2_2026-10-12.zip`，含下面四组镜像。
详细构建/清理清单、重建前manifest与IP备份见`../b2_refresh_20261012_163627/`。

默认重建：`build_coremark_b2.ps1`；默认选择脚本现在选择B2 performance_long，
`select_coremark_image.ps1 -RunMode Validation`则选择B2 validation。

## 最终采用配置（2026-10-11）

用户已决定采用 **B2：rv32im_zba_zicsr、O3、无LTO**，结束B3/B4后续对比。
当时正式基线为新BTB下的237.628390 CoreMark、2.851541 CoreMark/MHz；最新结果见本文首节。
性能和验证模式的既有上板记录均已通过，详见后文。

两份根目录活动DAT已备份并成对选择本包的`performance_long/`（4000次、83333333Hz）。
PDS工程两个内存IP的.idf INIT_FILE已备份并切回本包同目录的对应DAT绝对路径。
配置记录见`../adopted_coremark_config.json`。
该2026-10-11操作当时仅更新输入配置；2026-10-12初始化内容同步状态见上节，位流仍需重新生成。
B3/B4的镜像及历史文件已按用户后续确认删除，不再推进对比。

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

旧2200次DAT已清理，当前上板性能镜像固定采用4000次。
4000次是否达到10秒同样以实际串口时间为准。

## 当前四套独立文件

| 目录 | 模式 | 次数 | CPU_HZ |
|---|---|---:|---:|
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

## 当前 B2 比较基线

当前采用结果为241.580522 CoreMark、2.898966 CoreMark/MHz。
EX2 L0改动前同B2基线为237.628390/2.851541，详细同配置比较见本文首节。

performance 预期 seedcrc=e9f5、CRC=e714/1fd7/8e3a。
运行至少10秒并显示 `Correct operation validated` 才符合该性能运行的时间/CRC要求。
`crcfinal` 随次数变化，不要要求4000次也等于此前2200次的33ff。
本轮可先比较性能；确定候选配置后再补 validation 种子记录。

validation 选择命令使用 `-RunMode Validation -PackageDir fpga/pds/coremark_b2/validation`。
其预期 seedcrc=18f2、CRC=e3c1/0747/8d84，正常不打印 `CoreMark 1.0` 成绩行。

不传 PackageDir 默认选择B2 performance_long。切换模式后须同步两个内存IP初始化并生成新位流。

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
通用 `tests/coremark/build.ps1` 默认采用Zba+O3、无LTO，输出build/b2/sim_performance；官方核心源码未修改。
