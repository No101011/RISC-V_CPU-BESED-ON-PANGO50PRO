# B3：Zba + O2 + LTO

已编译 performance_long / validation（4000 次、83333333 Hz）和两组 10 次短仿真镜像。
上板性能版 `.text` 为 16948 B，验证版为 16944 B。

完整路径、IP 切换步骤、CRC 预期、B2 比较基线和一次重建 B3/B4 的命令，见
[B3/B4 测试说明](../coremark_lto_compare.md)。

推荐先使用 `performance_long/imem_coremark.dat` 与 `performance_long/dmem_coremark.dat`。
两份 DAT 必须成对选择，重新生成两个内存 IP 并构建位流。
编译及静态导出已完成；用户随后提供 validation 上板运行日志，结果见下文。
代理未运行 RTL 仿真或重新核对此次 PDS 时序；performance 上板记录仍待提供。

## 2026-10-11：B3 validation 上板通过

证据为用户粘贴的 UART 输出，原样保存于 `validation/board_validation_2026-10-11.log`。
参数与该模式 manifest 一致：O2 + LTO、4000 次、83333333 Hz、2000 字节。
seedcrc=18f2、list/matrix/state=e3c1/0747/8d84，匹配官方验证预期；crcfinal=5249
与此前同为4000次的验证运行一致。程序显示 Correct operation validated。

| 指标 | B2：O3，无LTO | B3：O2，LTO |
|---|---:|---:|
| 计时周期 | 1408802359 | 1440200765 |
| 时间（秒） | 16.905628 | 17.282409 |
| 验证迭代率（次/秒） | 236.607591 | 231.449212 |
| 周期/迭代 | 352200.589750 | 360050.191250 |
| 验证镜像 .text（字节） | 21836 | 16944 |

两组均为新BTB、4000次、83333333Hz和validation种子。
B3增加31398406周期（2.228730%），验证吞吐量低2.180141%；代码缩小22.403371%。
计时换算1440200765/83333333=17.282409249秒、4000/该时间=231.449211874次/秒，
与串口六位小数一致，运行超过10秒且小于32位计数器回绕时间。

B3同时改变了优化级别和LTO开关，不能仅据此认定LTO造成回退。
需要B3与当前RTL下B1 O2比较，B4与B2 O3比较，再判断LTO影响。
这份结果属于validation，不能作为performance正式成绩；B3 performance仍待上板日志。
原ZIP为构建时快照，后续记录以目录与manifest为准。
