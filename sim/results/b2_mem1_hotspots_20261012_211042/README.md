# 当前 B2：EX2 L0 + MEM1普通load实时转发热点统计

2026-10-12，ModelSim SE-64 2020.4，一次完整performance短仿真，10次迭代、TB 100MHz。
RTL CPU SHA256=825a7158b3eaf00e546f86ff4b22491ade322cb8a56d624ff9ca3000c797783e。
FUSE_EN/FUSE_F2及SUBWORD_FAST开启，SUBWORD_SPEC关闭；B2 Zba+O3，无LTO。
没有修改CPU RTL、TB观察器、宏、软件镜像、IP、FDC或PDS配置；四条待处理时序策略未实施。

## 检查结果

- 编译与最终仿真均0 Errors/0 Warnings，进程退出0，TB正常EXIT。
- ELF/HEX匹配，计时CSR PC=80002c00/80002c0c。
- seedcrc=e9f5，list/matrix/state=e714/1fd7/8e3a，10次crcfinal=fcaf，全部正确。
- UART Total ticks=3328865，与COREMARK_TIMED窗口MATCH，边界错误0。
- 33份输入文件前后哈希一致；所有PC桶与整体计数对账，CPI/比例重算及ELF函数映射检查通过。
- 软件的不足10秒ERROR及Errors detected仅由短仿真时长检查触发，不代表CRC错误。
- 此次仅performance热点统计，没有运行validation或完整ISA回归。

沙箱启动ModelSim遇到已记录的DLL重定位问题，随后沙箱外运行成功。
仿真内核执行5分22秒，run.ps1可复现；输出目录/库名固定，重复执行会覆盖本目录仿真产物。
统计口径为计时窗口；WHOLE_PROGRAM包含初始化和报表输出，不与计时窗口混用。

## 两项load优化前后的对比

对照为b2_hotspots_20261011_220300的同一B2 10次镜像：BTB已优化、EX2 L0和MEM1实时转发均未加入。
本次对比覆盖两项load优化，不能作为MEM1单项的独立A/B测量。

| 指标 | 两项load优化前 | 当前 |
|---|---:|---:|
| 周期 | 3507488 | **3328865** |
| 架构退休指令 | 2903833 | 2903833 |
| CPI_arch | 1.207882134 | **1.146369299** |
| 周期/迭代 | 350748.8 | **332886.5** |
| 仿真归一化吞吐/MHz | 2.851043254 | **3.004026898** |
| load依赖等待 | 321131 | **142508** |
| EX1 load等待 | 142508 | **142508** |
| EX2 load等待 | 178623 | **0** |
| MEM1 load等待 | 0 | 0 |
| MUL等待 | 129600 | 129600 |
| EX1 MUL等待 | 35640 | 35640 |
| EX2 MUL等待 | 93960 | 93960 |
| 分支误预测 | 39533 | 39533 |
| jump误预测 | 364 | 364 |

周期恰好减少178623，与EX2 load依赖等待消除量一致；周期降低5.092619%，吞吐提高5.365883%。
架构指令、融合对4710、分支/jump解析及误预测均不变，MUL等待不变。
load等待下降55.623095%。这次计时窗口所有剩余load等待均发生在EX1；不代表所有程序/场景EX2等待都为0。
当前上板4000次成绩3.004606 CoreMark/MHz仍作为性能结果；短仿真3.004027仅为估计，
每迭代比上板多64.184周期（约0.0193%），短/长运行热身差异不能作为严格逐迭代对账。

## 当前剩余瓶颈

计时区间load等待142508周期（4.280979%），MUL等待129600（3.893219%）；合计272108（8.174198%）。
load与MUL等待没有重叠，DRAM/MDU/CSR停顿均0；全程序范围另有MDU停顿，不应泛化为程序没有除法。

### load仍主要是链表依赖

core_bench_list占119981周期（load等待的84.192%），core_state_transition占20314（14.255%）。

| 等待消费者PC | 指令 | 周期 |
|---|---|---:|
| 80000da8 | bne a2,s10,... | 28950 |
| 80000da4 | lh a2,2(a4) | 28872 |
| 80000e60 | beq s8,a3,... | 27910 |
| 80000e5c | lbu s8,0(a4) | 27780 |

仍是lw→lh/lbu→branch链，每条链等待已缩短。EX2/MEM1转发不能直接解除load刚在EX1时的等待，
若进一步消除，需要更早得到数据/地址，可能增加当前已紧的时序压力；不主动实施待处理策略。

### MUL是下一项明确的性能候选

全部129600周期位于matrix_test，消费者：194c add 58320；1828 add 29160；1938 srai 29160；
1654 sw及172c add各6480。生产者1948 MUL贡献EX1/EX2各29160；1820与1930各贡献EX2 29160。
若能让这些EX2 MUL依赖周期全部减少一拍，候选节省93960周期，理想吞吐提升约2.904568%。
这是机会估计，不是已实现收益；需缩短真实结果延迟并同步hazard/forward，且守住现有setup +0.179ns。

### 分支预测保持不变

分支39533/529588误预测，准确率92.535141%；jump 364/63102，准确率99.423156%。
分支误预测函数：core_state_transition 19045，matrix_test 10697，core_bench_list 9307。
全部分支误预测包含方向错误；target_errors=17270与方向错误重叠，不应相加。
矩阵循环182c和1950各3241次误预测，值得以后按PC研究。RET仅299/13735误预测，优先级较低。
redirect=39897是事件计数，不是损失周期；frontend_empty机会周期39897也不能与其他桶随意相加。

## 文件

- performance.log / performance.csv：原始完整日志、两个scope的计数和元数据。
- hotspots.csv / hotspots_annotated.csv：原始PC桶及ELF函数/指令注释。
- summary.json / comparison.json：当前汇总及与历史基线逐项比较。
- inputs_before.json / inputs_after.json：输入哈希，CPU/L0/TB/宏/脚本等另有快照。
- run.ps1 / summarize.py / compare.py：复现运行、汇总校验和对比脚本。
