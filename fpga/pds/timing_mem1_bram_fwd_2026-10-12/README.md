# 普通 load MEM1 实时转发：实现时序分析

报告：PDS 2022.2-SP6.1 build138931，PG2L50H-FBG484-6，2026-10-12 19:30:55，Production、多corner。
原始报告、P&R资源/引脚、日志与本地RTL/FDC已保存快照，复制哈希一致，见report_sha256.json。
本次只读取现有报告并记录分析，未修改RTL/FDC/IP，未运行实现、仿真或下载。

## 已声明约束全部通过，但CPU余量缩小

All Constraints Met；所有setup/hold TNS/THS及失败端点均为0，最小脉宽通过。
Recovery/removal汇总为空，不能解释为额外验证了非空恢复/移除路径。

| 发射→捕获 | Slow setup ns | Slow hold ns | Fast setup ns | Fast hold ns |
|---|---:|---:|---:|---:|
| clkout0→clkout0 | 15.017 | 0.179 | 17.043 | 0.117 |
| clkout1→clkout0 | 0.630 | 0.253 | 1.980 | 0.099 |
| clkout1→clkout1 | **0.179** | 0.102 | 4.767 | **0.067** |
| clkout0→clkout1 | 0.321 | 0.268 | 1.858 | 0.103 |

CPU周期12ns，83.333333MHz；CPU setup余量179ps，约周期的1.49%。
此前17:02:10报告曾读取CPU setup +0.680ns，此次减少0.501ns；之前报告已被覆盖，该比较依据此前读取值。
10月11日有原始快照的新BTB基线CPU setup +0.935ns，包含不同RTL和布局布线，不应全部归因单一逻辑。
报告估算84.5952MHz，只是当前CPU时钟域估算，不是整机提频保证；建议保持83.333333MHz。

## 新增返回路径成为CPU瓶颈

最差路径：DRAM ADDR_LOOP[13]读输出QB0[16] → 原始返回/格式化 → 转发选择 → alu_b_fwd → alu_b →
EX1 ALU alu_raw → ID spec_base → 地址加法器 → spec_ld_waddr[13]，WNS +0.179ns。
第二条同样从DRAM返回出发，终点spec_addr_valid，WNS +0.188ns；第三条到spec_ld_waddr[9]，+0.270ns。
它不止是BRAM→EX1流水线寄存器：ID预算基址支持FWD_EX2取当前EX1 alu_raw，又串上一次地址计算。
spec_ld_waddr在!stall时无条件采样spec_addr18，即使spec_addr_valid最终为0，该数据寄存器路径仍被STA分析。

- 最差路径13级逻辑，数据路径11.347ns：逻辑4.586ns（40.416%），布线6.761ns（59.584%）。
- BRAM tco 1.644ns，紧接的QB_bus单根网络延迟2.301ns，是显著布线开销。
- 时钟偏斜-0.208ns；到达15.641ns含发射时钟插入延迟，不能称作15.641ns组合延迟。
- CPU最差hold仍是e2_pc[3]→BTB偶数bank写地址，+0.067ns，不是BRAM长返回路径。

后续优先研究拆开EX1实时ALU结果与ID预算地址的串联。保守取消ID的FWD_EX2预测捷径可以移除该数据来源，
但会失去部分D1/投机读机会，必须统计性能代价。只屏蔽spec_addr_valid不等于移除地址寄存器的长路径。
当前不修改代码；不要用false path或多周期约束掩盖会在一个周期内采样的真实路径。

## 最终P&R资源

| 资源 | 使用/总量 | 比例 |
|---|---:|---:|
| DRM | 49/85 | 57.65% |
| LUT（CLMA+CLMS） | 7083/35800 | 19.78% |
| FF（CLMA+CLMS） | 3208/71600 | 4.48% |
| Distributed RAM（报告计数） | 1604/9500 | 16.88% |
| APM | 4/120 | 3.33% |
| IO | 12/250 | 4.80% |

DRM为48个DRM36K及2个DRM18K等效49块：两份IROM16、DRAM32、L0 0.5、寄存器堆0.5。
10月11日旧BTB快照为48.5 DRM、6929 LUT、3040 FF、1586 Distributed RAM；
当前差额包含EX2 L0新增查询及本次MEM1转发与映射/布局变化，不能全归因MEM1。
LUT采用最终物理资源4734+2349；Device Map的6523及层次表6486是不同口径，不替代最终物理总数。
Distributed RAM计数不是KB，也不与LUT总数简单相加。

## 引脚与证据范围

top_prr.prt的全部12脚固定YES，与pins.fdc一致：V4/W4、P14/K19、8个LED。
report_timing_run.log仍提示UART/LED缺少外部input/output delay，不是物理引脚未约束；
All Constraints Met表示已声明约束通过，不代表外部UART/LED同步时序已全部验证。
本地myCPU SHA256=825a7158b3eaf00e546f86ff4b22491ade322cb8a56d624ff9ca3000c797783e。
报告时间及BRAM→转发→ALU路径与新增逻辑相符，但未独立核对已下载位流与源码/镜像哈希对应关系。
用户本次B2 performance为250.383850 CoreMark、3.004606 CoreMark/MHz，CRC/时长通过；
当前RTL B2 validation、ISA回归及新热点仿真仍待完成。
