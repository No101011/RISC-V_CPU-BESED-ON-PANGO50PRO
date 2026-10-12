# 官方源码重新生成的上板 CoreMark DAT

生成日期：2026-10-11。源码来自新下载的EEMBC官方HEAD快照，固定提交
`1f483d5b8316753a742cbf5590caf5bd0a4e4777`，详情及源码哈希见 `source_provenance.json`。
本次重新编译并导出两组完整文件，沿用项目裸机移植层。

## 配置

GCC15.2.0，rv32im_zba_zicsr、ILP32、O3、无LTO、newlib_nano。
两组均4000次、CPU_HZ=83333333、TOTAL_DATA_SIZE=2000，内存与CPU时钟1:1。
IROM=8192个32位字，DRAM=32768个32位字；DAT为ASCII、LF换行、无BOM。
实际代码21836字节（5459字），初始化数据3084字节（771字），其余补齐。

| 目录 | 模式 | seedcrc | list / matrix / state | 4000次crcfinal参考 |
|---|---|---|---|---|
| performance | 性能 | e9f5 | e714 / 1fd7 / 8e3a | 65c5 |
| validation | 验证 | 18f2 | e3c1 / 0747 / 8d84 | 5249 |

建议先测试performance，再测试validation；至少10秒并显示Correct operation validated。
validation正常不打印CoreMark 1.0性能成绩行。

## PDS 设置与测试步骤

检查时PDS两个活动IP的.idf初始化路径仍指向旧 `fpga/pds/coremark_b2/validation/`。
本次生成包未自动改变IP路径或根目录活动DAT。

1. 性能测试：把 `irom_bram` 的INIT_FILE设为本目录
   `performance/imem_coremark.dat`；把 `bram_dram` 的INIT_FILE设为
   `performance/dmem_coremark.dat`。请选择完整绝对路径。
2. 重新生成 **两个内存IP**，再运行Compile→Synthesize→Device Map→P&R→Report Timing→Generate Bitstream。
3. 核对83.333MHz时序，下载位流，UART使用9600-8-N-1文本接收并保存完整输出。
4. 验证测试：两个INIT_FILE一起切到本目录 `validation/` 下的对应文件，重复以上生成与下载步骤。

两份DAT必须来自同一模式目录；不能只换指令DAT。
程序报表中的include/map路径仍为build/b2/performance_long或build/b2/validation，因为本次沿用相同编译目录布局。

## 生成结果与范围

两种模式编译与链接均退出码0，日志无错误/警告诊断。
源码官方哈希、DAT的8192/32768字深度、32位HEX格式、无BOM和LF以及SHA256均已核对。
新DAT与之前B2相同模式的对应文件字节完全一致，这是相同源码、移植层和参数的重建结果。
该CoreMark包不读取或生成DIVU指令回归镜像，DIVU错误镜像替换属于另一项工作。

各模式目录包含两份DAT、ELF/HEX/BIN/map、构建参数头文件、build.log与build_manifest.json。
包汇总见 `build_summary.json`。本次未运行仿真、PDS或上板。

## 后续 performance 上板记录

用户提供重新生成包的performance串口结果，保存为 `performance/board_performance_2026-10-11.log`。
4000次、1402750453 ticks、16.833006秒、237.628390 CoreMark，归一化2.851541 CoreMark/MHz，
每迭代350687.613250周期。seedcrc=e9f5，list/matrix/state=e714/1fd7/8e3a，crcfinal=65c5，
Correct operation validated，运行时间与CRC要求均通过。
与之前新BTB+B2的performance计时周期完全一致（差0周期），符合新旧对应DAT字节一致的结果。
这是用户UART文本提供的运行证据，未独立采集串口或核对已下载位流哈希。
此次重新生成包的validation串口记录尚未提供；此前同一B2+新BTB validation已有正确的上板记录。
生成时ZIP保持为快照，后续串口记录以本目录和manifest为准。
