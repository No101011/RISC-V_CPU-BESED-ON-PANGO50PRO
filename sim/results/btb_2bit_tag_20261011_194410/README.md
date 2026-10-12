# BTB 两位方向计数器与标签：仿真记录

日期：2026-10-11。ModelSim SE-64 2020.4；TB 时钟100MHz。
软件采用 B1 的 Zba+O2、10次短镜像，未重新构建或切换活动DAT。
对照直接编译 `myCPU.sv.bak_prebtb_2bit_tag_20261011_193355_808`；
新版本编译当前 `rtl/soc/myCPU.sv`，没有通过覆盖RTL来切换版本。
两组performance使用同一ELF/HEX，计时CSR PC为80002660/8000266c。
输入文件哈希保存在 `input_sha256.json`。

## Performance 对照

下表均为 `COREMARK_TIMED`，包含开始CSR采样拍、排除结束CSR采样拍。
两组UART Total ticks与观察窗口均MATCH，均正常EXIT。
seedcrc=e9f5，CRC=e714/1fd7/8e3a，crcfinal=fcaf，两个版本完全一致。

| 指标 | 修改前 | 修改后 |
|---|---:|---:|
| 迭代次数 | 10 | 10 |
| 计时周期 | 3956123 | 3557698 |
| 周期/迭代 | 395612.3 | 355769.8 |
| 架构退休指令 | 2861378 | 2861378 |
| 融合后退休单元 | 2856818 | 2856818 |
| 融合对 | 4560 | 4560 |
| 架构CPI（重算） | 1.382594 | 1.243351 |
| 条件分支解析次数 | 531744 | 531744 |
| 条件分支误预测 | 168576 | 39505 |
| 分支准确率（重算） | 68.297527% | 92.570673% |
| 跳转误预测 | 4826 | 6742 |
| 预测重定向事件 | 173402 | 46247 |
| 依赖停顿周期 | 405784 | 517825 |
| 前端空队列机会周期 | 173402 | 46247 |
| 归一化吞吐量/MHz（短仿真估计） | 2.527727 | 2.810806 |

节省398425周期，计时周期降低10.071097%，吞吐量提高11.198955%。
条件分支方向错误减少129071次。跳转误预测增加1916次，整体周期仍降低；
本次数据没有定位跳转回退的具体原因。
依赖停顿桶增加并不等于整体性能回退：它与其他事件可能重叠，不能逐桶相加。

## Validation

新版本validation正常EXIT：10次、3566657计时周期，UART Total ticks对账MATCH。
seedcrc=18f2，CRC=e3c1/0747/8d84，crcfinal=c64e，三个算法CRC全部正确。
周期/迭代=356665.7；validation吞吐量不作为performance成绩。
证据为 `new_validation.log` 和 `new_validation.csv`。

## RV32I/M 指令回归

现有47项回归：46 PASS、1 FAIL、0 HANG。
失败项为 `rv32um-p-divu`，testnum=8（476周期）。
用修改前备份单独运行DIVU，同样testnum=8失败、同样476周期；旧历史日志也记录同一失败。
因此不能称全部指令测试通过；这项失败在BTB修改前已经存在，本次没有修改除法器。
证据为 `riscv_tests.log` 与 `baseline_divu.log`。

2026-10-11后续调查确认：本地DIVU镜像testnum=8/9/10除零预期错误地设置为80000000，
规范和官方divu.S预期均为FFFFFFFF，现有mdu.v除零返回值符合规范。
上面的46 PASS/1 FAIL保留为原始运行结果；该FAIL不能作为已证实RTL缺陷。
镜像纠正与新回归尚未执行，不能直接改记47 PASS。
完整静态调查见 `../divu_investigation_20261011/README.md`。

## 报表比例显示问题

原始日志/CSV中的部分CPI和比例显示不正确（包括CPI=0）。
`ratio_probe.sv` 独立复现了ModelSim 2020.4在自动task内，把packed数组切片
直接作为函数实参时的错误结果。复制至局部64位变量后调用函数，或直接进行实数运算，结果正常。
诊断输出见 `ratio_probe2.log`；没有改动正式TB。
本表和 `summary.json` 中CPI、预测准确率使用原始整数计数重算，保留原始日志/CSV供审计。

## 范围与复现

各次RTL编译均为0 Errors / 0 Warnings。
首次建立独立库时，脚本捕获vdel清理不存在库的提示，不属于RTL编译失败。
短CoreMark会打印不足10秒错误和Errors detected；此处CRC正确，该时间错误是短运行的预期结果。
这些数据不能作为官方10秒成绩，RTL仿真也不验证PDS setup/hold或实际资源占用。

`baseline_coremark.do`、`run_remaining.ps1`、`riscv_tests_isolated.do`、`baseline_divu.do`
保留本次命令。执行目录为仓库的 `sim/programs`。
`summarize.py` 核对日志CRC、CSV计时对账、指令统计关系和输入哈希，并生成 `summary.json`。
