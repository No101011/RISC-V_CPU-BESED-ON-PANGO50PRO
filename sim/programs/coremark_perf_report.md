# CoreMark 仿真性能报表

## 使用

从 `sim/programs` 运行原来的 `vsim -c -do coremark.do`。默认读取
`tests/coremark/build/imem.hex`、`dmem.hex` 和同目录的 `coremark.elf`。
运行结束打印报表，并生成当前目录的 `coremark_perf.csv`。

选定镜像和输出文件（以下命令在 `sim/programs` 中执行）：

```powershell
$env:COREMARK_IMEM_HEX = '../../tests/coremark/build/sim_validation/imem.hex'
$env:COREMARK_DMEM_HEX = '../../tests/coremark/build/sim_validation/dmem.hex'
$env:COREMARK_REPORT_CSV = 'coremark_validation_perf.csv'
vsim -c -do coremark.do
```

脚本使用 Python 标准库直接读取 ELF，不需要安装第三方库或 objdump。
Python 不在 PATH 时设置 `COREMARK_PYTHON` 为 Python 可执行文件路径。
ELF 在其他目录时设置 `COREMARK_PERF_ELF`。空的 `COREMARK_REPORT_CSV`
禁用 CSV。默认文件每次运行会覆盖，需要保存对比结果时指定不同文件名。

脚本核对 ELF 的 `.text` 与指令 HEX、所有 DRAM 已初始化节与数据 HEX，
再从 `start_time`、`stop_time` 函数定位各自唯一的 `csrr rd,mcycle`。
旧 ELF、混用 HEX、符号缺失或计时函数被 LTO 内联都会停止脚本，避免输出错误窗口。
为内联构建保留独立的计时函数符号后才能自动定位；临时只看全程序统计可设置
`COREMARK_PERF_ENABLE=0`。不要手填猜测的函数入口地址作为计时边界。

## 两种统计范围

- `WHOLE_PROGRAM`：复位释放到 EXIT（包含 EXIT 采样拍），或到 TIMEOUT。
  包含初始化、计算和报表输出。
- `COREMARK_TIMED`：EX1 真正推进的开始计时 CSR 采样拍，到结束计时 CSR
  采样拍；包含前者、排除后者。窗口周期与两次 CSR 读值的无符号差相等。
  多次计时（例如自动校准迭代次数）使用最后一组完成的窗口。
- `COREMARK_PARTIAL`：超时/退出时仍未读到结束计时 CSR，只打印部分计数，
  不计算每迭代周期或归一化吞吐量。

报表从 UART 抽取最终 `Total ticks`、`Iterations`、运行模式与 `CPU clock (Hz)`。
`Total ticks cross-check: MATCH` 表示观察窗口与软件实际报表一致。
程序未输出对应行时标为 unavailable；不匹配时标为 ERROR。
每迭代指标和归一化吞吐量仅在正常 EXIT、收到最终迭代次数且 ticks 对账一致后输出，
避免把校准窗口、未完成报表或不一致的窗口当成性能结果。
`mcycle` 软件端只读低 32 位，超过 2^32 周期的计时区间会提示范围限制。

TB 实际时钟固定为 100 MHz。镜像若使用其他 `CPU_HZ`，报表会提示 UART 的
秒数/成绩使用了不同频率；周期/迭代仍可用于分析。
归一化吞吐量是仿真估计，validation 吞吐量不作为性能成绩；短运行不满足
官方 10 秒规则。CRC 和官方规则状态仍以原 CoreMark UART 输出为准。

## 指标定义

| 指标 | 定义 |
|---|---|
| `retired_arch_instructions` | WB 的 `instret_pulse` 有效时，普通指令计 1、融合对计 2 |
| `retired_units` | 每次有效退休计 1，融合对也计 1 |
| `retired_fused_pairs` | 有效退休且带融合标志的数量 |
| `cpi_arch` | 同一窗口周期 / 架构指令数 |
| `cycles_per_retired_unit` | 同一窗口周期 / 融合后退休单元数 |
| `cycles_per_iteration` | 完整计时窗口周期 / 最终迭代次数 |
| `throughput_per_mhz_estimate` | 1,000,000 × 最终迭代次数 / 完整计时窗口周期 |
| branch / jump | 在 EX2 有效且未受后端反压时统计解析事件，非 WB 退休计数 |
| branch direction / target | 方向错误、跳转目标错误分别计数，同一分支可能两者都有 |
| jump mispredictions | 未预测为 taken 或目标错误的并集，包含旧报表遗漏的未预测跳转 |
| prediction redirects | `predict_wrong` 触发数，不解释为损失周期 |
| any stall cycles | 原全局 `stall` 为真的周期，四种原因的并集 |
| overlapping stall cycles | DRAM、dependency、MDU、CSR 中至少两种同时为真的周期 |
| dependency stall cycles | 原 `load_use_stall`，包括 load 和流水化乘法结果依赖 |
| load / mul dependency cycles | 基于 hazard 内实际源/目的寄存器匹配及结果未就绪条件，分别取并集 |
| load and mul dependency cycles | 本拍加载和乘法依赖同时存在 |
| stage dependency cycles | EX1/EX2/MEM1 实际依赖匹配分桶，同拍可重叠 |
| assertion runs | 相应信号由 0→1 的次数；窗口统计开始发生在窗口内的 run，不能当作依赖指令数 |
| frontend empty opportunity | 队头无有效指令，且没有全局 stall、没有 redirect 的周期 |
| no retirement cycles | 本拍没有有效退休，不解释为单一原因的损失周期 |
| D1 eligible probes | EX1 的 load 真正推进且预测地址有效时的一次查询 |
| D1 fastpath hits | 上述查询实际满足 D1 快速返回条件 |
| D1 SB / L0 selected | 命中时实际选择 store buffer 或 L0；SB 优先，二者互斥 |
| D1 misses | 合格查询未获快速返回，包括同址写冲突等保护条件；不是纯 L0 cache miss |

所有周期比例使用所在 scope 的周期作分母。架构退休与分支解析发生在不同
流水级，计时边界附近可能计入不同指令；CPI 表示该时间窗口的吞吐量。
各原因桶、阶段桶与无退休周期不能相加当成总损失周期。

CSV 使用 `scope,metric,value` 三列，包含原始计数和元数据，便于逐轮对比。
`retired_arch_instructions = retired_units + retired_fused_pairs` 是本核融合
计数的关系；`load + mul - both = dependency` 是依赖分桶的关系。

## 实现范围

新增统计全部位于 testbench，按 CPU 上升沿、DUT 非阻塞赋值前的信号采样。
EXIT/TIMEOUT 打印延后一小步，避免与统计线程在同一个仿真事件区竞争。
没有修改官方核心源码、软件计时方法、CPU 控制逻辑、上板镜像或 PDS 工程。
旧 RTL `u_perf` 计数器仍保留，其 `perf_instret` 是融合后单元口径；新报表
使用 testbench 观察器，不再把旧计数器的裸值附在报告末尾。

2026-10-11 检查记录：ModelSim 2020.4 的 vlog 编译和 vopt 展开均为
0 Errors / 0 Warnings；当前性能镜像与 10 次短验证镜像的 ELF/HEX 元数据匹配。
本次未运行 RTL 仿真，窗口与 UART ticks 的动态对账、统计数值和 CSV 内容尚待运行确认。

2026-10-11 后续动态检查：新BTB配合B1 Zba+O2、10次performance/validation镜像
均正常EXIT，CRC正确，UART ticks与观察窗口分别3557698/3566657，均MATCH。
对照修改前myCPU备份，同一performance镜像为3956123周期。
详细结果及原始CSV在 `sim/results/btb_2bit_tag_20261011_194410/`。
发现ModelSim 2020.4在自动task内将packed计数切片直接传给函数时，
部分CPI/比例错误地显示0；独立诊断中复制到局部64位变量后调用函数正常。
正式TB尚未修复此显示问题，不能使用其原始CPI/准确率字段作结论；
此次summary.json与README的比例均根据原始整数计数重新计算。
计时窗口对账、原始计数以及每迭代周期不受此次已观察到的显示问题影响。

## B2 PC 热点统计与比例修复（2026-10-11）

用户授权运行B2热点仿真后，现已补充可选的计时区间PC统计：

```powershell
$env:COREMARK_HOTSPOT_CSV = '../results/my_run/hotspots.csv'
```

输出目录需预先存在。使用当前新BTB RTL时，testbench输出
`scope,metric,pc,value` 四列CSV；仅在正常EXIT、完整计时窗口且UART ticks对账成功后导出。
每个新start_time采样会清空PC桶，因此与整体报表一样只保留最后一组计时窗口。

- load/mul消费者：按实际hazard信号归因到ID的`d_pc`，每个对应周期计一次。
- 生产者：分别归因到EX1、EX2、MEM1的load/mul PC；阶段桶可能重叠，不能当成互斥损失相加。
- branch：EX2解析事件及方向/目标错误，计数口径与现有整体计数一致。
- jump：分为JAL、标准RET（jalr x0,0(x1/x5)）、其他jump；互斥分组之和等于原jump总计。
- D1：EX1推进且load地址已就绪时的probe、hit、SB/L0选择、miss；这是地址已就绪查询的命中率，不是全部load或全部L0访问的命中率。

ModelSim 2020.4比例问题已修复：原始packed task输入先复制到局部64位数组，
比例使用现场`real'(...)`转换和除法，避免数组/切片作为嵌套函数实参时的错误。
仅复制到unpacked数组后继续调用函数仍会显示错误，因此最终修复采用现场计算。
独立诊断及两次完整B2运行已验证：原始计数、PC直方图完全一致，最终CPI与Python重算一致。

B2为Zba+O3、无LTO，10次performance @TB 100MHz：正常EXIT，CRC=e714/1fd7/8e3a，
seedcrc=e9f5，计时窗口3507488周期与UART MATCH；CPI_arch=1.207882134。
load依赖321131周期（9.156%），mul依赖129600（3.695%），计时区间MDU停顿0。
分支准确率92.535%，jump准确率99.423%；RET误预测299/13735。
按PC桶汇总与整体计数逐项核对，通过；函数/指令从匹配ELF和反汇编映射。

完整日志、CSV、注释后的PC清单、汇总脚本和复现命令在
`sim/results/b2_hotspots_20261011_220300/`。短仿真不足10秒提示为预期，正式分数继续采用上板B2成绩。
