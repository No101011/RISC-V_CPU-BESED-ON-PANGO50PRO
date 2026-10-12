# B4：Zba + O3 + LTO

已编译 performance_long / validation（4000 次、83333333 Hz）和两组 10 次短仿真镜像。
上板性能版 `.text` 为 30060 B，验证版为 30056 B，均在 32 KB IROM 容量内。

完整路径、IP 切换步骤、CRC 预期、B2 比较基线和一次重建 B3/B4 的命令，见
[B3/B4 测试说明](../coremark_lto_compare.md)。

推荐使用 `performance_long/imem_coremark.dat` 与 `performance_long/dmem_coremark.dat`。
两份 DAT 必须成对选择，重新生成两个内存 IP 并构建位流。
编译及静态导出已完成；用户随后提供 validation 上板日志，结果见下文。
代理未运行 RTL 仿真或重新核对此次 PDS 时序，performance 上板记录仍待提供。

## 2026-10-11：B4 validation 上板通过

用户粘贴的 UART 原样保存于 `validation/board_validation_2026-10-11.log`。
编译/链接参数与 manifest 一致：O3 + LTO、4000 次、83333333 Hz、2000 字节。
seedcrc=18f2、list/matrix/state=e3c1/0747/8d84，匹配官方验证预期；crcfinal=5249
与此前4000次验证结果一致，程序显示 Correct operation validated。

| 指标 | B2：O3，无LTO | B3：O2，LTO | B4：O3，LTO |
|---|---:|---:|---:|
| 计时周期 | 1408802359 | 1440200765 | 1402217102 |
| 时间（秒） | 16.905628 | 17.282409 | 16.826605 |
| 验证迭代率（次/秒） | 236.607591 | 231.449212 | 237.718775 |
| 周期/迭代 | 352200.589750 | 360050.191250 | 350554.275500 |
| 验证镜像 .text（字节） | 21836 | 16944 | 30056 |

同为当前新BTB、validation种子、4000次和83333333Hz，B4比B2节省6585257周期，
周期减少0.467437%，吞吐量提高0.469632%；比B3节省37983663周期，吞吐量提高2.708829%。
B4代码比B2增加8220B（37.644257%），验证版IROM剩余2712B；性能版30060B，剩余2708B。
本组结果显示O3+LTO配置在验证负载上的小幅收益，代码体积代价较大。

1402217102/83333333=16.826605291秒，4000/该时间=237.718775163次/秒，
与串口输出一致；超过10秒且未越过32位计数器回绕时间。
validation迭代率不能替代正式performance成绩，也不能直接与B2 performance的237.628390比较。
下一步优先测B4 performance_long，与B2相同模式对照；B3 performance也待补齐。
证据为用户UART文本，未独立核对下载位流哈希和本次PDS报告。
原ZIP保留为构建快照，后续记录以目录与manifest为准。
