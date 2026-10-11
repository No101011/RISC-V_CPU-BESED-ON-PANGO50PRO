# CoreMark 源码与上板结果核对（2026-10-10）

## 结论

当前性能运行的计算结果和计时换算正确。五个核心 C 文件及 coremark.h 与 EEMBC 官方源码相同，只有 CRLF/LF 换行区别。平台移植层为本项目定制。

初次核对时缺另一组验证记录及完整编译参数；后续已修复，并取得用户提供的两组上板输出。
当前 performance=209.697589 CoreMark、10.491299秒；validation=4000次、19.063306秒，均CRC通过。
官方开源规则要求的两组运行证据已补齐；机构认证或提交审核属于单独事项。

## 官方源码对比

固定对比版本：https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777

官方文件下载在 tmp/coremark_official_20261010。对 tests/coremark/src 下各文件进行 CRLF→LF 归一化后，逐字节比较全部相等。

| 文件 | 归一化后的本地与官方 MD5（相同） |
|---|---|
| core_main.c | 4a9e6dadce1ac3866381021fbe843fc9 |
| core_list_join.c | 9007fe7861b60ee6f210d156b62974c8 |
| core_matrix.c | 5fa21a0f7c3964167c9691db531ca652 |
| core_state.c | fb49e7605c125306575a83f14f5798ac |
| core_util.c | 45540ba2145adea1ec7ea2c72a1fbbcb |
| coremark.h | b0ec69b6c8e75853d06accb3b1bcf534 |

五个 C 文件还匹配官方 coremark.md5 清单。该版本官方清单中 coremark.h 的旧 MD5 为 8ca974c013b380dc7f0d6d1afb76eb2d，与官方当前头文件自身不一致；本地头文件与所固定版本的官方实际文件逐字节相等。

算法、工作负载、CRC 检查、计时边界、成绩计算逻辑均无本地改动。

## 平台移植

| 文件/配置 | 本地实现 |
|---|---|
| port/core_portme.c | volatile 种子、读取 mcycle、时间换算、结束标志 |
| port/core_portme.h | RV32 数据类型、单线程、STATIC 内存、CPU_HZ、编译信息 |
| port/ee_printf.c | 自写精简格式化输出，轮询 UART 忙状态 |
| port/syscalls.c、crt0.S、link.ld | 裸机系统调用、启动和内存布局 |
| build.ps1 / Makefile | RISC-V 编译、链接和镜像生成 |

官方允许修改 core_portme 配置和实现、迭代次数、编译构建选项；裸机移植指南要求平台提供 timer/printf 支持。本地自写 ee_printf 属于这种支持代码，并非修改核心算法。

官方裸机移植指南：https://github.com/eembc/coremark/blob/1f483d5b8316753a742cbf5590caf5bd0a4e4777/barebones_porting.md

## 当前上板结果与构建产物

证据为用户提供的串口 HEX，已保存至 coremark_board_2026-10-10.log；本次未重新采集串口或运行基准。

- 2200 次，874277070 ticks，CPU_HZ=83333333。
- 874277070 / 83333333 = 10.4913248819653 秒，打印 10.491325 正确。
- 2200 / 10.4913248819653 = 209.69706159627404，打印 209.697062 正确。
- seedcrc=e9f5，list=e714、matrix=1fd7、state=8e3a，匹配官方 performance run 的校验值。
- TOTAL_DATA_SIZE=2000；显示 Size=666 是三个算法各分配 2000/3 字节的正常结果。
- RTL 的 mcycle_lo 每个 CPU 时钟周期递增，包含停顿周期；不是用退休指令数代替时间。
- 串口成绩输出位于 stop_time 之后，UART 发送等待不计入核心负载计时。
- 已检查现存 ELF：start_time/stop_time 读取 mcycle，time_in_secs 使用除法；.rodata 含 83333333.0，seed4 为 2200，其余种子在清零的 BSS。
- build/imem.hex 的 4908 个程序字与 PDS imem_coremark.dat 前缀一致；剩余填充为 NOP（00000013）。build/dmem.hex 的 606 个字与 PDS dmem_coremark.dat 前缀一致，剩余为零。
- build.ps1 对五个核心 C 文件和平台 C 文件使用相同 CFLAGS，未设置 LTO 或 PGO。

## 初次审计发现的问题与实现边界（后续修复见末尾）

1. 官方规则要求种子 0,0,0x66 和 0x3415,0x3415,0x66 两组均验证成功。目前证据只有前一组。当前 port 硬编码 0,0,0（官方 main 转成 0,0,0x66），未实现 VALIDATION_RUN 切换；单独增加该宏不会自动改变本端口的种子。
2. 串口 FLAGS_STR 为 -O2 -march=rv32im，而构建脚本实际使用 -O2 -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow，另有段拆分、预处理定义和 nano.specs 等选项。打印字符串不影响执行，但正式报告应补全真实配置。现存 build_log.txt 是旧记录，不能充当本次完整构建命令记录。
3. CORE_TICKS 仅为 32 位，当前频率下可正确测量的持续时间必须小于约 51.539608 秒；当前 10.491325 秒在范围内。
4. 自写 ee_printf 会把大于 4000 的浮点数限制为 4000；当前时间和分数未触发。未来超过此数值时会错误显示。
5. core_portme.c 中“seed3 必须为零”的注释不准确，直接使用 0,0,0x66 同样是正确性能种子。
6. CoreMark/MHz 的正式报告还应说明代码/数据位置及内存时钟与核心时钟比例；当前 2.51636 是按 PLL 名义频率计算的归一化值。

官方运行与报告规则：https://github.com/eembc/coremark/blob/1f483d5b8316753a742cbf5590caf5bd0a4e4777/README.md#run-rules

本次执行源码比较和产物静态检查，没有修改测试程序、重编译或运行新测试。

## 后续：用户要求补全输出参数

在以上核对之后，已修改平台报表和构建脚本，由实际构建选项自动生成完整编译与链接参数，
补充 C 库、CPU 频率及代码/数据位置、内存时钟比例。已按原上板配置重编译并更新两份 DAT。
上文“串口参数不完整”描述针对原实测镜像；新版输出实现已修正，但尚未生成新版 bitstream 或上板复测。
原 ELF/HEX/DAT 保存在 `tests/coremark/_backup_pre_build_report_20261010/`，上文旧产物的比较结论对应该基线。
源码算法保持未改，另一组验证种子及计时器/浮点输出范围限制仍存在。

## 后续：补全官方 validation 模式

用户已提供完整参数版性能日志：10.491299秒、209.697589 CoreMark、三个CRC通过。
随后平台移植层增加 PERFORMANCE_RUN / VALIDATION_RUN 的官方种子切换，构建路径分离，
固定2000字节缓冲区，并导出带源码/镜像哈希的两组 PDS 镜像包。
验证种子已通过10次 RTL 仿真（seedcrc=18f2，CRC=e3c1/0747/8d84）；
短仿真不足10秒，不能作为正式验证运行记录。
活动 DAT 当前为4000次 validation，预计上板约19秒；需要重生成两内存IP和bitstream后取得实际板卡验证日志。
此前“未实现验证模式切换”问题已修复，真实板卡的另一组通过记录尚待补充。
计时器和浮点输出的数值范围限制仍适用，本次镜像的预计运行范围未触及限制。
操作说明与证据见 `coremark_official/README.md`。

## 后续：validation 真实板卡运行通过

用户已提供4000次实际板卡输出，保存为 `coremark_official/validation/board_validation.log`。
1588608811 / 83333333 = 19.063305808秒，打印19.063306正确；
4000 / 19.063305808 = 209.827195778，打印209.827196正确。
seedcrc=18f2，list=e3c1、matrix=0747、state=8d84，均正确，程序报告 `Correct operation validated`。
本次时间超过10秒并小于32位周期计数范围（约51.54秒），参数与已打包的validation镜像配置一致。
与已有performance实测一起，已补齐两组运行证据。对外性能成绩继续引用performance的209.697589，
不使用validation吞吐量作为CoreMark成绩。
