# 新 BTB 实现时序分析（2026-10-11）

原工程：`E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU`。
PDS 2022.2-SP6.1 build138931，Logos2 PG2L50H-FBG484-6，Performance 模式、seed=5。
`top.rtr` 报告时间 2026-10-11 19:41:59，Production 模型、multi corner。
保存原始报告快照与 SHA256，防止下一次实现覆盖。此次只分析报告、更新记录，未修改 RTL/FDC 或运行实现/仿真。

## 结论

**All Constraints Met**：125 MHz 输入、50 MHz 外设、83.333333 MHz CPU 当前声明的约束全部通过。
Setup TNS、Hold THS、失败端点数全部为零，最小脉宽也通过。
Recovery/removal 汇总没有条目，不代表额外检查了非空的恢复/移除路径。

| 发射 → 捕获 | Slow setup WNS (ns) | Slow hold WHS (ns) | Fast setup WNS (ns) | Fast hold WHS (ns) |
|---|---:|---:|---:|---:|
| clkout0 → clkout0 | +15.278 | +0.213 | +17.226 | +0.145 |
| clkout1 → clkout0 | +0.253 | +0.232 | +1.785 | +0.100 |
| clkout1 → clkout1 | +0.935 | +0.125 | +5.519 | +0.082 |
| clkout0 → clkout1 | +0.452 | +0.264 | +1.880 | +0.102 |

CPU slow setup 相比 10 月 10 日基线 +0.899 ns 增加 0.036 ns，裕量基本相当。
全局最小 setup 由旧基线 +0.483 ns 变为 +0.253 ns；全局最小 hold 由 +0.079 ns 变为 +0.082 ns。
这些是两次实现结果比较，不能把细小变化全部归因于某一 RTL 逻辑。

## CPU 关键路径

`u_pc_reg/pc[4] → BTB 奇数 bank valid 位查表/选择 → take_a → issue_b → take_b → succ_b[13] → u_pc_reg/pc[13]`。

- 9 级逻辑，数据路径延迟 10.700 ns：逻辑 2.079 ns（19.430%），布线 8.621 ns（80.570%）。
- PC[4] 网络扇出 1157，网络延迟 1.843 ns；BTB 后的一个选择网络延迟 1.859 ns。
- 报告的到达时间 14.991 ns 含发射时钟延迟 4.291 ns，不能当成组合路径延迟。
- 当前瓶颈位于取指/BTB/下一 PC 选择链，重点是地址扇出、存储组织与布线。
- 报告估算 CPU 最小周期 11.065 ns、90.3751 MHz，仅是当前实现的 CPU 域估算，不能作为整机安全提频承诺。

## 跨时钟路径

CPU→50 MHz 最紧路径为 `bridge_inst/seg_driver/count[4] → twin_controller_inst/status_buffer[4][4]`，setup +0.253 ns。
50 MHz→CPU 最紧路径为 `twin_controller_inst/sw[11] → Core_cpu/u_mem_wb_reg/w_mem_rdata[11]`，setup +0.452 ns。
两路时钟来自同一 PLL，按相关生成时钟分析；不能为掩盖这些路径而整体声明异步或 false path。
修改 PLL 频率后必须重新实现并检查两方向跨时钟路径与所有 corner。

## 最终 P&R 资源

| 资源 | 使用 / 总量 | 比例 |
|---|---:|---:|
| DRM | 48.5 / 85 | 57.06% |
| LUT（CLMA + CLMS） | 6929 / 35800 | 19.35% |
| FF（CLMA + CLMS） | 3040 / 71600 | 4.25% |
| Distributed RAM（报告计数） | 1586 / 9500 | 16.69% |
| APM | 4 / 120 | 3.33% |
| IO | 12 / 250 | 4.80% |

DRM 与旧基线一致。综合映射日志确认 `btb_mem_e`、`btb_mem_o` 均为 2048×19 bit，映射到 GTP_RAM256X1SP/GTP_RAM64X1DP（LUTRAM），新 BTB 已进入此实现。
Distributed RAM 的资源计数不是 KB，也不能与 LUT 使用数简单相加。
Device Map 的 LUT=6388，与最终 P&R=6929 属于不同阶段，此处采用最终 P&R 数据。

## 约束覆盖范围

`report_timing_run.log` 对 LED、UART 提示 Timing4086/4087：缺少外部 I/O 时序约束。
这是 input/output delay 的覆盖问题；全部 12 脚的物理位置仍已固定 YES。
UART 为异步串口，LED 无外部同步采样时钟，后续应按实际接口声明时序意图，不能随意补同步延迟数值。
因此 All Constraints Met 表示已声明约束通过，并不表示所有外部 I/O 时序已经验证。

报告之后生成的 `top.sbit` 时间为 19:42:57。此次未独立核对已下载镜像的哈希。
用户新 BTB+B2 串口性能成绩为 237.628390 CoreMark、2.851541 CoreMark/MHz，CRC 通过。
B2+新 BTB 的完整 validation 上板记录仍待补齐；既有 DIVU 回归失败另见 AGENTS.md。
