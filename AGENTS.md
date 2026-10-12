# AGENTS.md —— RISCV_CPU_BaseOn_Pangu 移植项目交接说明

> 给 AI 编码代理（Codex / Claude Code 等）的交接文档。请在开始任何操作前读完第 1、2、11 节。
>
> - **工作区（源码在这里）**：`E:\FPGA\github\RISCV\RISCV_CPU_BaseOn_Pangu`
> - **PDS 工程（在工作区之外，需要写权限）**：`E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU`
> - 最后更新：2026-10-12

---

## 0. 目标

把一颗 **7 级流水线 RV32IM 软核**从 Xilinx Kintex-7 移植到 **盘古50Pro 开发板**上，跑出**有效的 CoreMark 分数**。

- 开发板：**MES2L50HP**（盘古50Pro，深圳小眼睛科技 / meyesemi.com）
- 核心板：**MES-2L484 V1.4** → FPGA = **Pango Logos2 `PG2L50H-FBG484-6`**
- 工具：**PDS 2022.2-SP6.1**（`D:\realsoftwares\PDS_2022.2-SP6.1`）
- 仿真：ModelSim SE-64 2020.4（`D:\realsoftwares\modelsim\win64`）
- 工具链：`D:\realsoftwares\xpack-riscv-none-elf-gcc-15.2.0-1\bin`

> 2026-10-10 已按用户提供的 **盘古50Pro** 资料重新确认板卡和全部引脚。
> 资料目录：`E:\download\盘古50Pro开发板配套资料`。旧盘古50K 的 P20、R8/R9 和 LED 球号不适用。
> 用户选择 **V4/W4 的 125 MHz 差分晶振**；单端晶振实际是 Y18 的 27 MHz。

---

## 1. 当前状态（先看这里）

| 项目 | 状态 |
|---|---|
| CPU RTL / 外设 / CoreMark 软件 | CoreMark两模式通过；DIVU错误镜像已用官方源码重建替换，纠正后回归待运行；原始指令回归46 PASS/1 FAIL（详见第11节） |
| 器件切换 Logos2/PG2L50H | ✓ 已完成（工程 `_part` + 三个 IP 重生成） |
| `pll` IP | ✓ Logos2 GPLL 1.4，输入125 MHz，输出50.000 / 83.333 MHz |
| `irom_bram` IP | ✓ Logos2 ROM 1.8，32bit×8192，初值 `imem_coremark.dat` |
| `bram_dram` IP | ✓ Logos2 SDPRAM 1.10，32bit×32768，初值 `dmem_coremark.dat` |
| 引脚约束 | ✓ 50Pro 全部 12 脚已固定：差分时钟、UART、8 LED（见第 4 节） |
| PDS 流程 | ✓ 2026-10-11 新BTB实现与时序报告已核对，All Constraints Met；seed=5，单种子 |
| 上板 | ✓ 2026-10-12 EX2 L0+B2 performance用户UART通过：16.557626秒、241.580522 CoreMark、2.898966 CoreMark/MHz；当前新RTL+B2 validation待提供，旧RTL验证记录保留 |
| 最终采用配置 | B2：rv32im_zba_zicsr、O3、无LTO；2026-10-12四组镜像重编译、旧DAT清理、两个IP初始化均匹配B2 performance_long；用户已提供新性能运行结果，本轮PDS时序/资源及下载位流哈希未独立核对 |

最新新BTB实现 **DRM=48.5/85（57.06%）**；CPU `clkout1→clkout1` slow setup **WNS=+0.935ns、TNS=0**。
报告 `E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU\report_timing\top.rtr`（2026-10-11 19:41:59），
多 corner 结论 **All Constraints Met**；全部时钟对最小 setup +0.253ns，最小 hold +0.082ns。
快照与分析见 `fpga/pds/timing_btb_2026-10-11/README.md`；CPU关键路径已转为PC/BTB/下一PC选择。
旧实现基线（2026-10-10 21:03）CPU setup +0.899ns，全局最小setup +0.483ns、hold +0.079ns。
LED/UART缺少外部I/O时序约束的提示不等于引脚未固定；已声明内部时序约束全部通过。
全部12个引脚在 `place_route/top_prr.prt` 中为固定分配 YES。
8个并行种子曾发生内存分配失败，改为单种子 seed=5、parallel=1 后通过（PDS保存时省略默认值1）。
不要使用旧的 `top_timing_summary_after_hold_fix.txt`。
**上板CoreMark验收已通过**：用户提供的串口HEX已解码保存至 `fpga/pds/coremark_board_2026-10-10.log`。
83.333333MHz下成绩为 **209.697062 CoreMark，约2.51636 CoreMark/MHz**；运行时间超过10秒，
seedcrc=e9f5，list/matrix/state=e714/1fd7/8e3a，程序报告 `Correct operation validated`。
本次证据为用户贴出的串口数据；8个LED的实际结束状态尚未由用户确认。

**2026-10-10 后续软件更新**：参数完整版本已由用户上板运行，日志为
`fpga/pds/coremark_board_2026-10-10_full_params.log`：2200 次、10.491299 秒、209.697589 CoreMark，CRC 全通过。
随后已完善官方两种运行模式，分别生成 `fpga/pds/coremark_official/performance/` 和 `validation/` 镜像包。
五个核心 C 文件及 coremark.h 未改，打包时检查官方固定版本源码哈希。
validation 的 10 次 RTL 仿真已验证 seedcrc=18f2，list/matrix/state=e3c1/0747/8d84；
短仿真会报不足10秒，不能作为完整官方运行记录。
**当前活动 `imem_coremark.dat`、`dmem_coremark.dat` 已切到 validation（4000次，CPU_HZ=83333333）**。
用户随后已上板完成 validation：4000次，1588608811 ticks，19.063306秒，
seedcrc=18f2、CRC=e3c1/0747/8d84、crcfinal=5249，并显示 `Correct operation validated`。
日志在 `fpga/pds/coremark_official/validation/board_validation.log`；证据为用户粘贴的串口输出，非代理直接采集。
两组真实运行均超过10秒且CRC正确，已补齐官方开源规则要求的性能/验证两组运行证据。
对外性能成绩仍用 **209.697589 CoreMark（约2.51637 CoreMark/MHz）**；验证运行的209.827196不作为性能成绩。
上面的 PDS 时序数据是先前核对的实现基线，本次只核对了新串口日志，未重新检查用户此次PDS报告。
验证模式正常不打印 `CoreMark 1.0` 成绩行。切回性能镜像用 `fpga/pds/select_coremark_image.ps1 -RunMode Performance`。
切换前的活动 DAT 在 `fpga/pds/_backup_coremark_selection_20261010_234629_762/`；
更早原 ELF/HEX/DAT 在 `tests/coremark/_backup_pre_build_report_20261010/`。
详情与重建命令见 `fpga/pds/coremark_official/README.md`。

---

## 2. 目录结构（工作区）

```
rtl/core/          CPU 全部流水线（.v）
rtl/soc/myCPU.sv   CPU 顶层
rtl/perip/         top.sv / student_top.sv / perip_bridge.sv / uart.sv /
                   twin_controller.sv / dram_driver.sv / counter.sv / seg7.sv ...
rtl/include/defines.vh
sim/tb/tb_myCPU/tb_myCPU.sv   仿真台（自带 ROM/DAM 模型，不依赖 PDS 的 DRM 原语）
sim/programs/coremark.do      CoreMark 仿真脚本（MAX_CYCLES 可用环境变量覆盖）
sim/programs/riscv_tests.do
tests/coremark/               CoreMark 源码 + port/（BSP）
tests/coremark/build.ps1      构建脚本（两套预设：仿真 / 上板）
fpga/pds/pins.fdc             ★ 时钟 + 引脚约束（PDS 直接引用这个文件）
fpga/pds/imem_coremark.dat    ★ 上板 ROM 初值（8192 行 32bit HEX，无 BOM，LF）
fpga/pds/dmem_coremark.dat    ★ 上板 DRAM 初值（32768 行，当前 validation 初始数据781字）
fpga/pds/coremark_official/   官方 performance / validation 镜像与核对文档
fpga/pds/select_coremark_image.ps1  同步切换两份活动 DAT，先校验再备份
fpga/pds/mk_imem_dat.ps1      把 build/imem.hex 补齐成 8192 行的 .dat
fpga/pds/README.md            ★ 详细笔记（第 10 节是当前 50Pro 适配，务必看）
fpga/pds/pins_template.fdc    已作废（旧占位模板），不要导入
```

---

## 3. 时钟链与频率

```
核心板 125MHz 差分 → V4(P)/W4(N) → GTP_INBUFDS → PLL(clkin1)
   CLKIN=125, IDIV=1, MDIV=1, FDIV=6 → VCO = 750 MHz
   ODIV0=15, DUTY0=15 → clkout0 = 50.000 MHz → uart + twin_controller
   ODIV1= 9, DUTY1= 9 → clkout1 = 83.333 MHz → CPU
```

- `GTP_INBUFDS` 的 `TERM_DIFF=OFF`：核心板 R73 已有 100Ω 外部端接。
- FDC 的差分脚标准使用 **SSTL15D_I / VCCIO=1.5V**，与 50Pro DDR3 demo 的 V4/W4 配置一致。
- PLL 端口名：`clkin1 / clkout0 / clkout1 / lock`（Logos2 锁定输出叫 `lock`）。
- `pins.fdc`：主时钟周期 8ns；clkout0 ×2÷5（20ns）；clkout1 ×2÷3（12ns）。
- 本次保持两路输出频率，CoreMark `CPU_HZ=83333333 / ITERS=2200` 和 UART 参数不变。
- 改 CPU 频率时需同步 PLL `.idf` 并重生成 IP、FDC 和 CoreMark 镜像。

---

## 4. 50Pro 引脚约束（`fpga/pds/pins.fdc`）

| 信号 | 脚位 | Bank / VCCIO | PDS 标准 |
|---|---|---|---|
| `clk_125m_p` / `clk_125m_n` | **V4 / W4** | R5 / 1.5V | SSTL15D_I |
| `i_uart_rx` | **P14** | L5 / 3.3V | LVCMOS33 |
| `o_uart_tx` | **K19** | L4 / 3.3V | LVCMOS33 |
| `led[0..7]` | **F13 F14 E13 E14 E16 D16 F16 E17** | L3 / 3.3V | LVCMOS33 |

- LED1..8 高电平点亮；UART 为 CP2102 的 USB Type-C 接口，9600-8-N-1。
- 来源：`3_Hardware/盘古50Pro硬件使用手册.pdf`，印刷页14、33（表3-5）、40–41（表3-9）；
  `MES-2L484-V1.4核心板原理图.pdf`（R5 供电及 R73）；厂商 demo 01_led_test、04_uart_test、07_ddr3_test。
- 125MHz 差分时钟另有一对 F6/E6，属于 HSST 专用脚；本设计使用 **V4/W4**。
- 所有顶层物理 I/O 均已有位置约束；P14 属于 share pin，PDS 会有提示。
- 旧 P20 + 6 LED 配置仅保留在 `*.bak_pre50pro125mhz` 中，不能用于 50Pro 上板。

---

## 5. 内存与外设映射（RTL 侧，别改）

| 地址 | 用途 |
|---|---|
| `0x8010_0000 ~ 0x8012_0000` | 片上 DRAM **128KB**（`bram_dram`，15 位字地址 `[16:2]`） |
| `0x8020_0000/4` | SW0/SW1（`twin_controller`） |
| `0x8020_0010` | KEY |
| `0x8020_0020` | SEG |
| `0x8020_0040` | **LED 寄存器**（32 位，`top.sv` 取 `[7:0]` 输出到 8 个 LED 脚） |
| `0x8020_0050` | CNT |
| **`0xF000_0000`** | **魔法 UART：写=输出一个字符** |
| **`0xF000_0004`** | 写：CoreMark 结束标志（板上会让 LED 全亮）= `cm_done` |
| **`0xF000_0008`** | 读：bit0 = 发送忙（**软件必须先轮询再写字符**，否则 9600 波特下丢字符） |

- IROM：`irom_bram` **例化两份**（双发取指），`addr = pc[14:2]`，1 拍读延迟
- DRAM：`OUTPUT_REG=0` = **1 拍读延迟**（`dram_driver.sv` 注释写明 latency-1）
- 魔法 UART 桥：`perip_bridge.sv` 里做 CPU 域请求翻转 → `top.sv` 里 50MHz 域同步 + 发 `tx_start`，
  与 `twin_controller` 复用同一个 UART（**CoreMark 文本优先**；跑 CoreMark 时别开数字孪生上位机）
- 字符输出带流控：`tests/coremark/port/ee_printf.c` 与 `syscalls.c` 都会先读 `0xF000_0008` 等不忙

---

## 6. 构建流程

### 6.1 CoreMark（两套预设，别搞混）

```powershell
# 仿真镜像（ITERS=10, CPU_HZ=100MHz）
powershell -File tests\coremark\build.ps1 -Toolchain D:\realsoftwares\xpack-riscv-none-elf-gcc-15.2.0-1\bin

# 上板镜像（ITERS=2200, CPU_HZ=83333333）
powershell -File tests\coremark\build.ps1 -Toolchain <同上> -CpuHz 83333333 -Iters 2200

# 生成 PDS 用的 ROM 初值（8192 行）
powershell -File fpga\pds\mk_imem_dat.ps1
```
> ⚠️ **`tests/coremark/build/imem.hex` 是"最后一次构建"的那份**：跑完仿真镜像它就是仿真镜像 ✗，
> 上板前必须重跑上板预设 + `mk_imem_dat.ps1` + 在 PDS 里重新生成 `irom_bram` IP。
> ⚠️ `ITERS × 397215 ≥ 10 × CPU_HZ` 才满足 CoreMark 的 10 秒规则。
> 实测：**397,215 ticks/iter**、CPI 1.385。

### 6.2 PDS 五步

```
Compile → Synthesize → Device Map → Place & Route → Generate Bitstream
```
- 约束文件 `fpga/pds/pins.fdc` 由 `.pds` 中的相对路径直接引用源码仓库这一份，PDS 每次 Compile 都会重读 ✓
- `.dat` 初值文件同理（ROM/IP 里存的是绝对路径）

---

## 7. 仿真流程（ModelSim）

```powershell
$env:LM_LICENSE_FILE='D:\realsoftwares\modelsim\LICENSE.TXT'
$env:MGLS_LICENSE_FILE='D:\realsoftwares\modelsim\LICENSE.TXT'
$env:PATH="D:\realsoftwares\modelsim\win64;$env:PATH"
cd sim\programs
$env:COREMARK_MAX_CYCLES='20000000'
cmd /c "vsim -c -do coremark.do > sim_D.log 2>&1"
```
**验收标准**（`2K performance run parameters` / `seedcrc : 0xe9f5` / `[0]crclist : 0xe714` /
`[0]crcmatrix : 0x1fd7` / `[0]crcstate : 0x8e3a` / `cycles ≈ 4,010,729` / `CPI 1.385`）。
`ERROR! Must execute for at least 10 secs` 是**预期**的（仿真预设跑不到 10 秒），不是失败。

---

## 8. 已验证的结论（别重复踩）

- **CoreMark 功能正确**：仿真三个 CRC 全对；`-Iters 2 -CpuHz 40000` 能打出 `CoreMark 1.0 : …` 格式 ✓
- **时序（PGL50H-6 上，仅供参考）**：250MHz 挂（-6.303）；100MHz 单种子 -0.546、多种子 seed_5 后 +0.027；
  **最终降到 83.33MHz（N=12）留余量**。关键路径始终是 `spec_ld_waddr/spec_ld_lane` 的扇出锥（单根网络 ≈1.8ns）
- **DRM**：PG2L50H 共 **85 块 DRM36K**（=3060Kbit）；本设计 ROM 8×2 + DRAM 32 ≈ **48/85** 够用 ✓
- 老 Kintex-7 工程本身也是**时序不收敛**的（257MHz、WNS -1.791），所以这是在"原设计就紧"的基础上移植

---

## 9. 上板与 JTAG（历史排查）

2026-10-10 用户已在真实板卡运行并收到有效CoreMark串口报表；以下为此前驱动问题记录。

- 下载器 = **FTDI FT2232**（`VID_0403&PID_6010`），板上 USB 也走它
- 曾经的问题：**Windows 11 25H2 + 内核隔离(内存完整性) 拦住 2014 版 FTDI 2.12.00 驱动** →
  `Code 39 / 0xC000007B` → PDS 报 `Open config cable fail` / `JtagServer-0306 No devices detected`
- 处置：把驱动换成 Windows 更新推的 **FTDI 2.12.36.20**（装完驱动库里能看到 `ftdibus.inf_amd64_*  2.12.36.20`）
- 仍待确认：设备当前是否已枚举、是否出现 FTDI JTAG 设备；CoreMark 串口应检查 **CP2102** 的 COM 口、
  系统日志里是否还有 `\Driver\FTDIBUS failed to load`
- 排查手法：`Get-PnpDevice`、`Get-WinEvent`（System / CodeIntegrity）、`setupapi.dev.log`、
  `C:\Windows\System32\DriverStore\FileRepository` 里的包内容

---

## 10. 环境坑（都踩过）

| 坑 | 说明 |
|---|---|
| **`.dat` 文件不能有 BOM** | 有 BOM 会让 PDS 报 `IPCompiler 0055: Failed to load the initial memory data`。用 `UTF8Encoding($false)` 写，**纯 LF** |
| **PDS 只在退出时把工程写盘** | 在 GUI 里改了 IP/约束后，磁盘上的 `.pds` 可能还是旧的；判断状态前先确认 PDS 已关闭 |
| **IP 的器件记录在 `.idf` 里** | 换器件必须重开 IP 对话框（或新建 IP），只改工程器件不够 |
| **`*_init_param.v` 走 `` `include ``** | 初值数据内联在被 `` `include `` 的文件里，**不需要**加进工程源文件列表 |
| **别导入 `pins_template.fdc`** | 里面是 76 个 `{TODO}` 占位，会报一堆错 |
| **PS 5.1 写中文 `.ps1` 要留 BOM** | 用工具改过会丢 BOM → PS 5.1 按 GBK 解析报语法错 |
| **Codex/代理的 shell 沙箱** | 本机 DSH 的沙箱运行器坏了（`--temp is not a directory`），命令需完全权限；raw shell 写 `fpga\pds\` 被拒时改用写文件工具 |
| **备份命名约定** | `*.bak_pre<改动名>`（如 `pll.v.bak_pre50mhz`）；工作区里另有 `_backup_pre_board_pins\` |

---

## 11. 给下一位代理的建议动作

2026-10-12 用户要求删除除B2外的CoreMark文件。整批删除旧包、备份、审计、历史仿真资料被自动审批拒绝，
理由是恢复/追溯资料未被单独明确授权；不得绕过拒绝，剩余历史资料需用户明确确认后再删除。
已改用较安全范围：删除554个可重建的非B2 ELF/HEX/BIN/对象/反汇编/映射、旧编译库文件及B1/LTO构建脚本。
所有历史LOG/JSON/ZIP、旧备份、reclone副本和审计资料保留，不能声称已全部清除非B2文件。
默认coremark.do指向B2 sim_performance；通用build.ps1/Makefile默认Zba+O3无LTO且输出B2仿真目录，
mk_imem_dat默认读B2 performance_long，B2构建脚本不再提供2200次包。中文PS1保留UTF8 BOM。
B2四组镜像、活动DAT、官方六文件、CPU RTL和ISA用例哈希核对未变；未运行新构建、测试或PDS。
删除前范围清单和保护哈希在fpga/pds/b2_refresh_20261012_163627/rebuildable_cleanup_plan.json。
原被拒绝的更大范围清单为同目录non_b2_cleanup_plan.json，后续执行前应重新核对存在路径、范围与授权。

2026-10-12 用户提供EX2 L0查询后B2 performance_long上板结果：4000次、83333333Hz，
1379802185 ticks、16.557626秒、241.580522 CoreMark、2.898966 CoreMark/MHz、344950.546250周期/迭代。
实际输出Zba+O3无LTO、build/b2/performance_long、PERFORMANCE_RUN=1，与当前manifest编译/链接参数一致。
seedcrc=e9f5、CRC=e714/1fd7/8e3a、final=65c5，Correct operation validated，超过10秒且计时换算吻合。
同B2改动前1402750453 ticks相比节省22948268周期，周期降1.635948%、吞吐升1.663156%。
与仅LW影子估计1.662046%接近：按4000次外推省22937200，实测多省11068周期，不能当逐次命中对账。
新性能基线更新为241.580522/2.898966；本轮新RTL+B2 validation仍待提供，B4 validation不替代此记录。
日志在fpga/pds/coremark_b2/performance_long/board_performance_ex2_l0_2026-10-12.log，README、manifest、汇总和采用配置已更新。
证据为用户UART文本，本轮PDS时序/资源与下载位流/镜像哈希未独立核对；没有改RTL/镜像/IP或运行新仿真/实现。

2026-10-12 用户授权重生成B2并删除其他未采用DAT，已完成四组B2构建：
performance_long/validation（4000、83333333Hz）及sim_performance/sim_validation（10、100MHz）。
GCC15.2.0 Zba+O3无LTO，编译/链接0退出无warning/error；官方6文件哈希、ELF/HEX、DAT格式/深度通过。
活动DAT切到B2 performance_long，选择脚本默认也切该包；B2构建脚本默认不再生成2200次DAT。
当前ROM已由用户更新为B2；RAM旧生成内容仍B4，本次调用PDS原始Tcl初始化生成器更新RAM常量并同步包装INIT_FILE。
先复现旧RAM全部常量一致再生成B2，最终解码ROM8192/RAM32768字均与B2 performance_long匹配。
IP Compiler的-batch尝试不被支持，实际是Tcl生成初始化常量，未宣称运行完整GUI IP重生成。
CPU RTL/宏/约束未变；没有运行动态仿真、完整PDS实现、位流生成或下载。
清理50个旧/重复CoreMark DAT及旧ZIP内40个DAT条目；B1/B3/B4/A1/fresh/reclone/旧备份/2200版/旧解码DAT被移除。
源码、ELF/HEX、历史日志和参数记录保留，ISA测试DAT保留；目前普通CoreMark DAT共10份（四组B2+活动副本）。
新包fpga/pds/coremark_b2_2026-10-12.zip，构建/清理/核对/旧manifest及IP备份在fpga/pds/b2_refresh_20261012_163627/。
下一步从Compile重新生成位流并下载，确认新RTL+B2实际performance/validation；旧位流没有自动更新。

2026-10-12 用户确认最近validation UART来自选择B2 performance_long两份DAT后的实现，已定位IP初始化未同步。
B2 DAT哈希仍与构建manifest一致；两个.idf指向B2 performance_long（10-11 21:57:17）。
但生成包装irom_bram.v:49、bram_dram.v:78仍标注B4 validation，init_param.v为10-11 21:37生成。
只读解码全部INIT参数后，ROM8192字、RAM32768字与B4 validation逐字一致（0差异），
与B2 performance_long分别差7498/748字，RAM还嵌入完整B4/LTO/validation报告参数。
因此当前状态是配置路径已切B2而生成IP仍为B4，与本轮UART一致；没有板上位流读回。
需要重新打开两个内存IP确认B2路径并生成，再重新走实现/位流/下载；本次没有代为生成或改任何RTL/IP/DAT。
原生成文件快照、解码DAT、路径/哈希/比较JSON和只读脚本在fpga/pds/ip_init_audit_20261012/。

2026-10-12 用户在自行加入仅LW EX2 L0读口后提供上板日志，实际镜像为B4 O3+LTO validation，
4000次、83333333Hz、1378509297 ticks、16.542112秒、241.807098次/秒。
seedcrc=18f2、CRC=e3c1/0747/8d84、final=5249，显示Correct operation validated，计时换算通过。
同配置前次B4 validation 1402217102 ticks相比节省23707805周期，周期降低1.690737%、吞吐提高1.719815%。
若下载位流唯一变化为EX2 L0查询，则支持约1.7%的收益；与B2短仿真影子估计量级接近，不能精确对账。
本轮不是B2，也不是performance成绩；采用B2的决定未更改，新RTL+B2 performance结果仍待提供。
原始日志在fpga/pds/coremark_b4/validation/board_validation_2026-10-12.log，README及结果JSON已追加。
证据为用户UART文本，下载位流/镜像哈希及本轮PDS时序未独立核对。
没有修改RTL、活动DAT、IP或运行仿真/实现。

2026-10-12 用户自行加入仅LW的EX2 L0第二查询口后要求检查，静态接线检查与示例一致。
rtl/core/l0_cache.v增加ld2查询；myCPU.sv增加MEM1/WB同字store守卫、mem1_fwd_pre数据来源和e2_ld_ready命中。
普通BRAM读和WB写回保留；未使用总stall门控命中，SUBWORD_SPEC仍关闭。
ModelSim vlog编译和vopt展开均0 Errors/0 Warnings、退出码0，输入哈希前后相同。
本次没有修改CPU RTL，没有运行动态仿真、PDS或上板；新RTL的CRC/性能/时序尚未验证。
原WNS=+0.935ns仅是改动前实现基线，不能直接作为本次新RTL时序结论。
记录、编译脚本/日志、源码快照及输入哈希在sim/results/ex2_l0_review_20261012_160451/。

2026-10-12 用户授权在TB观察EX2实际地址并运行B2仿真，已完成只读L0影子查询。
观察器为sim/tb/tb_myCPU/ex2_l0_shadow.svh，coremark.do可选COREMARK_EX2_SHADOW_CSV开启。
ModelSim编译/最终仿真0 Errors/0 Warnings，正常EXIT、CRC正确，计时3507488与UART MATCH。
原有全部计数及热点CSV与前次B2逐项一致，RTL/宏/软件镜像SHA256未变。
EX2 DRAM查询544892、原始/安全命中268487、守卫后数据不一致0。
当前EX2 load依赖178623，其中安全命中且可解除等待57429：LW57343、半字0、字节86。
静态机会占总周期1.63733%，理想吞吐增幅1.66458%，不是新RTL的实测提速。
最热两个LW da0/e58分别覆盖27893/26880次，改善LW→LH/LBU地址依赖；
字段LH da4和LBU e5c本轮全部L0未命中，其后的分支等待未覆盖。
建议若实施优先仅LW的EX2查询口，覆盖99.85%的机会；SB-only子字转发另有523次，收益小。
保守阻止MEM1和WB同字store，核对格式化后数据；本轮原始命中未遇阻止案例，不能视为一致性边界测试。
结果、输入哈希、快照、复现/汇总脚本在sim/results/b2_ex2_shadow_20261012_131140/。
没有改CPU RTL、宏、镜像、IP、时钟、活动DAT或PDS配置；实现后时序/资源/板测仍待验证。

2026-10-11 用户授权运行当前B2热点仿真，已完成ModelSim SE-64 2020.4两次完整运行及比例诊断。
B2 Zba+O3、无LTO，performance 10次 @TB 100MHz；宏FUSE_EN/FUSE_F2、SUBWORD_FAST开启，SUBWORD_SPEC关闭。
编译/展开和最终仿真0 Errors/0 Warnings，正常EXIT，seedcrc=e9f5、CRC=e714/1fd7/8e3a，10次crcfinal=fcaf。
UART Total ticks=3507488，与窗口MATCH；CPI_arch=1.207882134，归一化仿真估计2.851043254。
不足10秒ERROR属于短仿真时长检查，不是CRC错误，正式成绩仍采用B2上板237.628390/2.851541。
load依赖321131周期（9.156%），mul129600（3.695%），MDU/DRAM/CSR停顿0；分支准确率92.535%，jump99.423%。
新增仅TB的PC桶，所有桶与整体计数逐项对账；load消费者core_bench_list=240163（74.787%）、
core_state_transition=71016（22.114%），主要热点是lw→lh/lbu→branch依赖链。
mul全部位于matrix_test；EX1等待35640、EX2等待93960。RET仅299/13735误预测，应降低RAS优化优先级。
ModelSim比例bug已修复为局部64位数组+现场real转换，继续传数组元素给函数仍会错；
独立诊断通过，重跑前后原始计数及PC直方图完全一致，最终CPI/比例与Python重算一致。
脚本、日志、CSV、PC/函数注释、输入哈希及快照在`sim/results/b2_hotspots_20261011_220300/`。
仓库沙箱启动vsim报DLL重定位，按AGENTS已记录的工具限制，沙箱外运行成功。
本次只改sim/tb/tb_myCPU/tb_myCPU.sv观察器、coremark.do和说明；没有改CPU RTL、宏、软件镜像或PDS配置。

2026-10-11 用户明确停止后续对比测试并决定采用B2（Zba+O3、无LTO）。
正式基线维持237.628390 CoreMark、2.851541 CoreMark/MHz，4000次、83333333Hz。
已用select_coremark_image.ps1将两份活动DAT成对切回`coremark_b2/performance_long`，
活动DAT备份在`fpga/pds/_backup_coremark_selection_20261011_215715_639/`。
发现PDS两个.idf INIT_FILE仍指向B4 validation，已备份后切到B2 performance_long的对应绝对路径。
IP配置备份在PDS工程`_backup_select_b2_20261011_215717_251996/`；生成文件及板上位流未因此更新。
用户下次下载前应重新加载工程中的IP配置，重生成irom_bram/bram_dram及位流。
选定配置记录在`fpga/pds/adopted_coremark_config.json`；B3/B4产物和验证结果保留。
本次没有运行任何对比测试或修改CPU RTL，不再主动推进B3/B4测试。

2026-10-11 用户提供B4 O3+LTO validation上板日志：4000次、1402217102 ticks、
16.826605秒、237.718775次/秒；seedcrc=18f2、CRC=e3c1/0747/8d84、crcfinal=5249，
Correct operation validated，时间与CRC通过，编译/链接参数与B4 validation manifest一致。
日志在`fpga/pds/coremark_b4/validation/board_validation_2026-10-11.log`，证据为用户UART文本。
同模式B2 O3无LTO相比节省6585257周期，吞吐量提高0.469632%；比B3提高2.708829%。
代码30056B，比B2的21836B增加37.644257%，验证版32KB IROM余2712B。
B3/B4 validation均已上板通过，performance两组仍待日志，validation迭代率不作为正式CoreMark成绩。
本次仅记录/分析日志，未改RTL/镜像/IP或重新核对PDS时序/下载位流哈希。

2026-10-11 用户提供B3 O2+LTO validation上板日志：4000次、1440200765 ticks、
17.282409秒、231.449212次/秒；seedcrc=18f2，CRC=e3c1/0747/8d84，crcfinal=5249，
Correct operation validated，时间和CRC通过。参数与B3 validation manifest一致。
日志保存在`fpga/pds/coremark_b3/validation/board_validation_2026-10-11.log`，证据为用户UART文本。
同模式B2 O3无LTO（1408802359 ticks、236.607591次/秒）相比，周期增加2.228730%，吞吐量低2.180141%。
该比较同时改变O2/O3与LTO，不能单独归因LTO；validation迭代率不能替代performance正式成绩。
B3 performance和B4实际运行记录仍待提供；本次未修改RTL/镜像/IP，也未重新核对PDS报告或位流哈希。

2026-10-11 用户要求一次编译B3/B4供当前RTL上板对比，已完成
`fpga/pds/coremark_b3/`（Zba+O2+LTO）和`coremark_b4/`（Zba+O3+LTO）。
各包含performance_long/validation（4000次、83333333Hz）与sim_performance/sim_validation（10次、100MHz）。
性能.text为16948/30060B，验证.text为16944/30056B，均在32KB IROM内；八组最终编译链接0退出、无warning/error。
通用build.ps1新增可选-Lto，编译/链接同时使用相同优化级别和-flto，默认仍无LTO。
移植层修正align_mem缺少原型（void*输入，仍按8字节对齐），mcycle asm增加memory clobber；
LTO模式的start_time/stop_time使用noipa保留计时边界与TB定位符号。六个官方核心源码哈希未变。
重建用`fpga/pds/build_coremark_lto.ps1`，步骤见`fpga/pds/coremark_lto_compare.md`。
官方源码哈希、ELF/HEX和计时符号已静态核对；本次未运行仿真/PDS/上板，CRC运行验证待完成。
没有改CPU RTL、时钟、IP、约束或选择活动DAT；用户需成对切换IP INIT_FILE并重生成两内存IP和位流。

2026-10-11 用户授权写入 BTB 改动：先对当前 `rtl/soc/myCPU.sv` 做完整备份，
备份为 `rtl/soc/myCPU.sv.bak_prebtb_2bit_tag_20261011_193355_808`，复制后SHA256一致。
随后将BTB从15位/项改为19位/项，新增两位饱和方向计数器与PC[14]标签；
EX2有效条件分支无论跳转与否都训练，JAL/标准RET始终预测跳转，RET限定jalr x0,0(x1/x5)。
训练受rst/e2_valid/stall_back门控，误预测纠正当拍仍训练该EX2分支。
保留双槽取指、队列预测快照、单层RAS和现有纠正逻辑，未切换软件镜像。
写入时未运行编译、RTL仿真或PDS；随后用户编译完成并授权仿真，结果如下。
随后新BTB的资源及setup/hold已于2026-10-11核对，最新数据见第1节及下文时序记录。

2026-10-11 BTB仿真已完成（ModelSim SE-64 2020.4，TB=100MHz）：
使用B1 Zba+O2的10次短镜像，新BTB performance/validation CRC均正确，
seedcrc分别e9f5/18f2，CRC分别e714/1fd7/8e3a和e3c1/0747/8d84。
计时周期分别3557698/3566657，两次UART Total ticks均与TB窗口MATCH，正常EXIT。
修改前备份同一B1 performance镜像为3956123周期；新版本减少10.071097%，
短仿真吞吐量提高11.198955%，分支准确率68.297527%→92.570673%。
跳转误预测4826→6742，具体原因未定位。短运行不足10秒不是正式成绩。
RV32I/M现有47项回归：46 PASS、1 FAIL、0 HANG；DIVU testnum=8失败。
修改前备份单独运行DIVU也在testnum=8、476周期失败，确认该失败在BTB改动前已存在。
没有因此修改除法器或其他RTL。各次RTL编译均0 Errors / 0 Warnings。
正式TB的部分CPI/比例显示错误：独立诊断复现ModelSim自动task内packed切片
直接传函数参数得到错误比例，复制到局部64位变量后正常；正式TB本次未改。
汇总根据原始整数计数重算比例，原始日志/CSV保留。
日志、汇总、输入哈希和复现脚本在 `sim/results/btb_2bit_tag_20261011_194410/`。
汇总脚本已核对CRC、计时对账、融合/依赖计数关系及输入哈希，全部符合上述记录。
仿真测试过程没有修改CPU RTL、软件镜像或PDS工程；用户随后提供新BTB上板结果，见下文。

2026-10-11 仿真报表更新：统计观察器仅在 `sim/tb/tb_myCPU/tb_myCPU.sv` 中，
`sim/programs/coremark.do` 从匹配 HEX 的 ELF 自动定位计时 CSR 采样 PC。
新增 `COREMARK_TIMED` / `WHOLE_PROGRAM`、融合架构指令计数、真实 hazard 归因、
分支方向/目标拆分和 CSV 输出。用法与口径见 `sim/programs/coremark_perf_report.md`。
本次 ModelSim vlog 编译及 vopt 展开均为 0 Errors / 0 Warnings，
当前 build/ 性能镜像和 build/sim_validation/ 短验证镜像的 ELF/HEX 元数据均匹配。
未运行 RTL 仿真；新的窗口对账和数值尚待运行确认。
旧 `u_perf.perf_instret` 仍是融合后单元数，新报表使用 TB 独立计数器。
CPU RTL、官方 CoreMark、活动 DAT、PDS 工程均未因这次报表修改而更新。

2026-10-11 B1 镜像已生成：`fpga/pds/coremark_b1/` 包含
performance(2200)、performance_long(4000)、validation(4000) @83333333Hz，
以及两组 10 次 @100MHz 短仿真镜像。全部为 RV32IM+Zba+Zicsr、O2、无 LTO。
每组 .text=19508B，反汇编有51个静态Zba位置，官方核心源码哈希和ELF/HEX均匹配。
代理未运行 B1 仿真、PDS 或上板测试。用户随后提供 B1 performance 上板日志：
2200次、870744965 ticks、10.448940秒、210.547680 CoreMark、2.526572 CoreMark/MHz，
seedcrc=e9f5，CRC=e714/1fd7/8e3a，crcfinal=33ff，显示 Correct operation validated。
相比 A1 周期减少0.403753%、吞吐量提高0.405389%；B1 validation模式仍待用户测试，
本次未重新核对PDS时序。日志保存至 `fpga/pds/coremark_b1/performance/board_performance_2026-10-11.log`。
工作区活动 DAT 经哈希核对仍为旧 A1 validation；PDS当前IP初始化路径未核对。
`tests/coremark/build.ps1` 新增可选 `-Isa` 和 `-Python`，默认保持旧 A1 配置；
`select_coremark_image.ps1` 新增可选 `-PackageDir`，不指定仍选择原官方包。
用法、恢复命令、CRC 预期和不足10秒处理见 B1 README。完整重建用
`fpga/pds/build_coremark_b1.ps1`，仅生成独立文件，不自动选择镜像。

用户选择节省时间，直接比较 B2。2026-10-11 已生成 `fpga/pds/coremark_b2/`，
目录结构与 B1 相同，全部 Zba+O3、无 LTO；推荐先上板 performance_long(4000)，
避免2200次提速后不足10秒而再次重建。每组.text=21836B、43个静态Zba位置，
官方源码哈希、ELF/HEX均匹配。计时CSR PC=80002c00/80002c0c。
代理未运行 B2 仿真/PDS/上板测试，生成过程未选择活动DAT。构建脚本
`build_coremark_b2.ps1` 使用通用 build.ps1 新增的 `-Optimization O3`；默认仍O2。
与B1的395793.165909周期/迭代、2.526572 CoreMark/MHz比较，详情见B2 README。
用户随后提供 B2 performance_long 上板日志：4000次、1583923553 ticks、19.007083秒，
210.447866 CoreMark、2.525374 CoreMark/MHz、395980.888250周期/迭代；
seedcrc=e9f5、CRC=e714/1fd7/8e3a、crcfinal=65c5，显示 Correct operation validated。
性能运行时间与CRC通过；比B1吞吐量低0.047407%，.text大11.933566%，目前优先保留B1。
次数不同且差异很小，尚不能确定具体优化回退原因。B2 validation仍未提供上板记录，
本次未重新核对PDS时序。日志在 `fpga/pds/coremark_b2/performance_long/board_performance_2026-10-11.log`。

用户随后提供新BTB+B2 performance_long上板日志：4000次、1402750453 ticks、
16.833006秒、237.628390 CoreMark、2.851541 CoreMark/MHz、350687.613250周期/迭代。
seedcrc=e9f5、CRC=e714/1fd7/8e3a、crcfinal=65c5，Correct operation validated。
同为B2 O3、4000次、83333333Hz，相比旧BTB减少181173100周期，
周期降低11.438248%、吞吐量提高12.915562%。证据为用户UART文本，未独立采集。
日志保存为 `fpga/pds/coremark_b2/performance_long/board_performance_btb_2bit_tag_2026-10-11.log`，
保留修改前日志；manifest/build_summary/README追加新结果，没有覆盖旧基线。
B2+新BTB的validation上板记录随后已提供，见下文；提供performance UART时尚未核对新PDS时序，后续核对见下文，下载镜像哈希仍未独立核对。
此前O2/O3排序属于旧BTB；新硬件下不能用旧B1成绩判定O3优势。

2026-10-11 用户生成时序报告后，新BTB实现已核对：19:41:59多corner报告All Constraints Met，
slow setup四组WNS依次为15.278（0→0）、0.253（1→0）、0.935（1→1）、0.452（0→1）ns；
fast hold四组WHS依次为0.145、0.100、0.082、0.102ns，全部TNS/THS/失败端点为0。
CPU最差路径pc[4]→BTB查表→take_a/issue_b/take_b→succ_b[13]→pc[13]，9级，
逻辑2.079ns、布线8.621ns（80.57%），pc[4]扇出1157。估算90.3751MHz不作为整机提频承诺。
最终P&R DRM48.5/85不变，LUT6929/35800、FF3040/71600、Distributed RAM1586/9500。
综合日志确认两个2048×19bit BTB bank映射LUTRAM；12脚物理约束全部YES。
UART/LED外部I/O时序未约束提示仍存在，同PLL跨时钟路径保留相关时钟分析。
原始报告与哈希保存至 `fpga/pds/timing_btb_2026-10-11/`。此次没有改RTL/FDC或运行实现/测试。

2026-10-11 用户提供新BTB+B2 validation上板日志：4000次、1408802359 ticks、
16.905628秒、236.607591 Iterations/Sec、352200.589750周期/迭代，CPU_HZ=83333333。
seedcrc=18f2，list/matrix/state=e3c1/0747/8d84，与本地官方core_main.c预期一致；
crcfinal=5249，显示Correct operation validated，运行超过10秒，时间和迭代率换算吻合。
串口接收软件的三个时间戳将Iterations/Compiler字段分段，整理版只移除标记并连接字段。
原始及整理日志分别保存至 `fpga/pds/coremark_b2/validation/board_validation_btb_2bit_tag_2026-10-11_raw.log`
和同目录 `board_validation_btb_2bit_tag_2026-10-11.log`，更新两组manifest/build_summary/README。
新BTB+B2 performance/validation两组上板记录均已补齐，对外性能采用237.628390 CoreMark、
2.851541 CoreMark/MHz；validation迭代率不作为性能成绩。证据为用户UART文本，非代理采集。
此次未修改RTL、活动DAT、IP/FDC或运行仿真/实现，下载镜像哈希未独立核对。
已知DIVU testnum=8回归失败仍未修复，不能把CoreMark通过解释为全部ISA测试通过。

2026-10-11 用户要求调查DIVU失败，静态核对已确认本地镜像错误：
`tests/unofficial_test_data/rv32um-p-divu.dat` 与.txt第43/49/55行均为80000eb7，
将testnum=8/9/10的除零预期商设成80000000；规范与当前官方divu.S要求FFFFFFFF。
`rtl/core/mdu.v` 的除零分支返回FFFFFFFF符合规范；`sim/run_riscv.sh:42` 已记录并跳过该镜像。
因此前文“DIVU已有失败/未修复”是原始回归现象，不应再归类为已证实的RTL缺陷。
本次未修改RTL或测试镜像、未运行新仿真；旧日志没有失败时x30实际值。
建议备份后将两文件三处预期指令改为fff00e93（addi x29,x0,-1），再运行纠正后的回归。
当前保留46 PASS/1 FAIL原始计数，另注明DIVU测试基准无效；尚不能记录47 PASS。
完整调查、指令解码、输入哈希与官方链接在 `sim/results/divu_investigation_20261011/README.md`。

2026-10-11 用户要求官方重新clone CoreMark并编译。Git clone遇到失效本地代理与直连TLS失败，
改从EEMBC官方codeload取得HEAD ZIP（archive注释提交1f483d5b8316753a742cbf5590caf5bd0a4e4777）。
本次官方源码快照下载成功，Git clone未成功；没有修改全局Git配置或关闭证书验证。
在 `tests/coremark_official_reclone_20261011/rebuild_workspace/tests/coremark/` 独立接入项目port，
从新下载源码编译B2 performance/validation（Zba+O3、4000次、83333333Hz、newlib_nano）。
两组退出码0，编译日志无error/warning诊断；.text均21836B、初始数据3084B。
六个官方核心文件与现有src规范化字节一致，ELF/指令DAT/数据DAT与原B2分别字节完全一致。
日志、官方源码、独立包、SHA256比较与获取说明在 `tests/coremark_official_reclone_20261011/README.md`。
本次仅重新编译/导出/比较，未运行仿真/PDS/上板、未修改RTL/IP/FDC或选择活动DAT。

2026-10-11 用户授权用新源码替换错误代码，已获取官方riscv-tests提交
7b68f7b91f827f8d94cc1c57ff123752c5c8f704的divu.S及scalar/test_macros.h，保持官方内容不变。
在 `tests/official_riscv_divu_20261011/` 增加项目x26/x27/x3结束标志适配和链接脚本，
用GCC15.2.0编译RV32IM/ILP32镜像，代码260B；静态解码检查全部9项输入和预期常量正确。
已替换 `tests/unofficial_test_data/rv32um-p-divu.dat/.txt/.dump`，新增同目录官方.S。
第8/9/10项均加载FFFFFFFF，DAT/TXT保留98字；SHA256为ac4c1d80f021c87a15799a17e576829624dbe2e585d199ee7d68f24a9643609d。
原文件备份到 `tests/unofficial_test_data/_backup_pre_official_divu_20261011_205151_365291/`，哈希一致。
`sim/run_riscv.sh`取消DIVU跳过并使用实际统计用例数；ModelSim .do本来就加载该镜像无需变更。
详情、源码来源、重建脚本、ELF/BIN与编译日志见 `tests/official_riscv_divu_20261011/README.md`。
本次未运行RTL仿真或完整回归，尚不能记为47 PASS；没有改CPU RTL、CoreMark或活动DAT。

2026-10-11 用户要求重新生成上板CoreMark DAT，已从新下载官方源码的独立工作区重新编译，
输出到 `fpga/pds/coremark_fresh_20261011/performance/` 与 `validation/`。
两组为B2 Zba+O3、4000次、83333333Hz，.text21836B、初始化数据3084B，编译退出码0。
官方源码哈希与两份DAT格式/深度/哈希已核对，新包与原B2对应DAT字节完全一致。
当前PDS活动irom_bram/bram_dram.idf的INIT_FILE均指向旧coremark_b2/validation目录；
用户测试新包时须成对改为新包所选模式的两份DAT，再重生成两个内存IP及bitstream。
新包README列明PDS测试步骤和CRC预期，含ELF/HEX/BIN/map/日志/manifest，另有同名ZIP。
本次未选择根目录活动DAT、修改IP/RTL或运行仿真/PDS/上板。

用户随后提供新官方源码重生成包的performance上板结果：4000次、1402750453 ticks、
16.833006秒、237.628390 CoreMark、2.851541 CoreMark/MHz、350687.613250周期/迭代。
seedcrc=e9f5、CRC=e714/1fd7/8e3a、crcfinal=65c5，Correct operation validated，时间与CRC通过。
计时周期与之前新BTB+B2完全一致（差0周期），且重建DAT已确认字节一致。
日志在 `fpga/pds/coremark_fresh_20261011/performance/board_performance_2026-10-11.log`，
已更新新包manifest/build_summary/README。证据为用户UART文本，未独立采集或核对下载位流哈希。
新包validation本轮复测日志尚未提供，原B2+新BTB的validation上板通过记录仍保留。

1. 读 `fpga/pds/README.md` 第 10 节，按 **50Pro** 的资料核对板卡。
2. 若修改 RTL/IP/FDC，重跑 Compile → Synthesize → Device Map → P&R。
   核对 `device_map/top.pcf` 的全部引脚、DRM，以及 `report_timing/top.rtr` setup/hold。
   多种子运行则另看所选 `place_route/seed_*/top.rtr`，必须确认日期和对应配置。
3. 性能运行已通过，完整参数日志见 `fpga/pds/coremark_board_2026-10-10_full_params.log`；保留两份性能基线。
   validation 上板亦已通过，日志见 `fpga/pds/coremark_official/validation/board_validation.log`。
   当前活动 DAT 为 validation；若切换或修改镜像，仍须重生成两内存IP与bitstream并保存新日志。
4. 用 **CP2102** 串口，9600-8-N-1、文本/ASCII接收；最近性能基线为2200次、10.491299秒、
   CoreMark=209.697589、三个CRC通过。validation 基线为4000次、19.063306秒、seedcrc=18f2、CRC=e3c1/0747/8d84。
   结束时应亮8个LED，实际灯态仍待用户确认。
5. 需要历史细节时按关键词检索 `_session_export/对话记录_精简.md`，不要整篇读取。
