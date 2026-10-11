# AGENTS.md —— RISCV_CPU_BaseOn_Pangu 移植项目交接说明

> 给 AI 编码代理（Codex / Claude Code 等）的交接文档。请在开始任何操作前读完第 1、2、11 节。
>
> - **工作区（源码在这里）**：`E:\FPGA\github\RISCV\RISCV_CPU_BaseOn_Pangu`
> - **PDS 工程（在工作区之外，需要写权限）**：`E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU`
> - 最后更新：2026-10-10

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
| CPU RTL / 外设 / CoreMark 软件 | ✓ 完成，仿真通过（三个 CRC 全对） |
| 器件切换 Logos2/PG2L50H | ✓ 已完成（工程 `_part` + 三个 IP 重生成） |
| `pll` IP | ✓ Logos2 GPLL 1.4，输入125 MHz，输出50.000 / 83.333 MHz |
| `irom_bram` IP | ✓ Logos2 ROM 1.8，32bit×8192，初值 `imem_coremark.dat` |
| `bram_dram` IP | ✓ Logos2 SDPRAM 1.10，32bit×32768，初值 `dmem_coremark.dat` |
| 引脚约束 | ✓ 50Pro 全部 12 脚已固定：差分时钟、UART、8 LED（见第 4 节） |
| PDS 流程 | ✓ 2026-10-10 Compile → Synthesize → Device Map → P&R → Report Timing 全部完成；seed=5，单种子 |
| 上板 | ✓ 用户提供 performance 和 validation 两组实际串口报表：10.491299秒 / 19.063306秒，均CRC通过；性能成绩209.697589 |

本次 **DRM=48.5/85（57.06%）**；CPU `clkout1→clkout1` slow setup **WNS=+0.899ns、TNS=0**。
报告 `E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU\report_timing\top.rtr`（2026-10-10 21:03），
多 corner 结论 **All Constraints Met**；全部时钟对最小 setup +0.483ns，最小 hold +0.079ns。
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
