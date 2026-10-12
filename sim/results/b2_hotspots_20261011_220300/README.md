# B2 当前 RTL 的 CoreMark 热点仿真

日期：2026-10-11；ModelSim SE-64 2020.4，B2 Zba+O3、无LTO。
使用现有 `fpga/pds/coremark_b2/sim_performance/` 的ELF和两份HEX，没有重新编译软件。
10次performance、TB=100MHz；当前宏FUSE_EN/FUSE_F2开启，SUBWORD_FAST开启、SUBWORD_SPEC关闭。
统计仅覆盖软件start_time/stop_time之间，排除初始化和打印。

## 运行与核对

- 编译及展开、最终仿真：0 Errors / 0 Warnings，正常EXIT。
- seedcrc=e9f5、list/matrix/state=e714/1fd7/8e3a，均匹配官方performance预期；10次crcfinal=fcaf。
- UART Total ticks=3507488，与CSR采样区间和TB周期窗口完全MATCH；无边界错误。
- 观察器按PC汇总的22类桶（零值桶可不输出）均与整体计数对账，jump分类也对账成功。
- 两次完整运行原始整数计数和PC直方图完全一致；第二次的CPI/比例已修复并与Python重算核对。
- 运行仅0.03507488秒，UART的不足10秒ERROR及Errors detected来自官方运行时长检查，CRC没有失败。

仿真估计2.851043254迭代/秒/MHz，周期/迭代350748.8。
当前正式上板B2：2.851541 CoreMark/MHz，周期/迭代350687.61325（4000次）。
短仿真每迭代多0.01745%，存在迭代次数、初始状态和镜像布局差异，不将短仿真作为官方成绩。

## 计时区间总体结果

| 指标 | 结果 |
|---|---:|
| 周期 | 3507488 |
| 架构退休指令 | 2903833 |
| 融合后退休单元 | 2899123 |
| 融合对 | 4710 |
| CPI_arch | 1.207882134 |
| load依赖周期 | 321131（9.1556%） |
| mul依赖周期 | 129600（3.6950%） |
| 总依赖周期 | 450731（12.8505%） |
| load/mul重叠周期 | 0 |
| DRAM / MDU / CSR停顿 | 0 / 0 / 0 |
| 条件分支解析 / 误预测 | 529588 / 39533，准确率92.5351% |
| jump解析 / 误预测 | 63102 / 364，准确率99.4232% |
| JAL解析 / 误预测 | 49367 / 65 |
| RET解析 / 误预测 | 13735 / 299，准确率97.8231% |
| 其他jump | 0 |
| D1地址已就绪查询 / 命中 | 393163 / 211861，约53.8863% |
| SB / L0被选中 | 53648 / 158213 |

分支方向错误39533、目标错误17270存在重叠，不相加；误预测次数不是损失周期。
无退休周期、前端空周期、依赖阶段等指标也不能相加当作总开销。

## 1. load：主要是链式地址与子字读取依赖

按等待消费者函数归因：

| 函数 | load依赖周期 | 占load依赖桶 |
|---|---:|---:|
| core_bench_list | 240163 | 74.7866% |
| core_state_transition | 71016 | 22.1143% |
| matrix_test | 3240 | 1.0089% |

最集中的两条依赖链位于core_bench_list：

```text
80000da0: lw  a4,4(a5)
80000da4: lh  a2,2(a4)            # 等待地址a4：56802周期
80000da8: bne a2,s10,80000d98     # 等待数据a2：57900周期

80000e58: lw  a4,4(a5)
80000e5c: lbu s8,0(a4)           # 等待地址a4：54669周期
80000e60: beq s8,a3,80000dac      # 等待数据s8：55820周期
```

这四个消费者贡献225191周期，占整个load依赖桶约70.1244%。
链表函数内地址已就绪的D1查询140965次、命中138286次，约98.10%；
此命中率不包括尚不能预测地址的load，因此不能据此认为链式load没有开销。
优化优先调查load数据到下一条load地址、以及lh/lbu到branch的就绪时机。
扩大L0容量是否有用，需要进一步拆分未命中和地址未就绪原因，本次没有得到缓存冲突类型统计。

## 2. mul：全部集中于matrix_test

93960次连续依赖区间，EX1归因35640周期、EX2归因93960周期，合计129600。
消费者PC：

| PC | 指令 | 等待周期 |
|---|---|---:|
| 8000194c | add t4,t4,a5 | 58320 |
| 80001828 | add t3,t3,a5 | 29160 |
| 80001938 | srai a6,a5,2 | 29160 |
| 80001654 | sw a4,-4(a3) | 6480 |
| 8000172c | add a2,a2,a4 | 6480 |

前一个生产者80001948为MUL，后面紧跟ADD，产生两拍等待；
80001820与80001930的MUL和消费者之间有一条独立指令，仍有一拍等待。
应优先研究MUL低32位结果提前转发，MULH系列可保持较长通路。
若每个现有乘法依赖区间都少一拍且其他条件不变，理论节省93960周期（总周期2.6788%），
吞吐量约提高2.7526%；这只是理想估算，不保证时序和真实运行收益。

## 3. 分支：重点看状态机，RAS优先级降低

| 函数 | 条件分支误预测 | 占误预测桶 |
|---|---:|---:|
| core_state_transition | 19045 | 48.1749% |
| matrix_test | 10697 | 27.0584% |
| core_bench_list | 9307 | 23.5424% |

矩阵循环结束分支8000182c、80001950各3241次误预测，值得调查循环退出预测；
状态机数据相关分支80001ed0、80001ed8分别3120、2720次。
RET误预测299次，占全部预测redirect事件39897次的约0.75%，
因此当前B2下多层RAS的优先级低于load/mul和条件分支优化。
除法器在计时窗口停顿0，优化除法对本组CoreMark热点帮助很小。

## 文件与复现

- `performance.log` / `performance.csv`：最终正确显示的运行日志和两范围统计。
- `hotspots.csv`：计时区间PC原始计数；`hotspots_annotated.csv`：函数、偏移和指令映射。
- `summary.json`：完整计数、函数排名、原始输入SHA256、检查结论。
- `first_*`：比例修复前首轮运行，保留错误显示和相同原始计数供对照。
- `report_ratio_check.sv/.do/.log`：独立诊断复用实际报表任务，验证现场real转换。
- `tb_myCPU_before.sv` / `coremark_before.do`：修改前备份；`*_used`为最终运行输入快照。
- `run.ps1` / `summarize.py`：复现脚本。

从仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File sim/results/b2_hotspots_20261011_220300/run.ps1
& 'C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' sim/results/b2_hotspots_20261011_220300/summarize.py
```

ModelSim在Codex沙箱内启动出现DLL重定位错误；本轮使用已授权的沙箱外执行完成。
只修改TB观察器、运行脚本和报表说明，没有修改CPU RTL、宏、CoreMark镜像、IP、时钟或约束。
