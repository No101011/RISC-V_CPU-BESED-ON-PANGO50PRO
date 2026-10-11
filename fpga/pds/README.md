# 把 Vivado 的 BRAM 移植到 PDS（紫光同创）—— 用哪个 IP、怎么配

> **当前状态见第 10 节（2026-10-10，盘古50Pro / Logos2）。第 1–9 节包含旧器件和旧板卡记录，当前引脚、时钟和验收以第 10 节及 `pins.fdc` 为准。**

本机 PDS：`D:\realsoftwares\PDS_2022.2-SP1-Lite`（IP 模板路径：
`ip\module_ip\ipml_flex_ram\...`，下面的字段名都取自该版本的 IP 配置界面脚本 `ui.tcl`）。

结论先给：

| Vivado 里的东西 | RTL 里的例化名 | PDS 里应该用的 IP |
|---|---|---|
| Block Memory Generator = **Simple Dual Port RAM**，32bit × 65536，字节写使能（`bram_dram`） | `dram_driver.sv` → `bram_dram` | **Module / Memory / DRM → DRM Based Simple Dual Port RAM**（伪双口 RAM） |
| Block Memory Generator = **单口 ROM**，32bit × 4096，`.coe` 初始化（`irom_bram`） | `student_top.sv` → `irom_bram` | **Module / Memory / DRM → DRM Based ROM** |

**不要选** `Distributed *` 那一组：那是用 LUT 拼的，65536 深会直接把 LUT 资源吃光。
`DRM` = Pango 的专用块 RAM（相当于 Xilinx 的 BRAM，DRM18K / 36K）。

> IP 版本差异：你的工程所属器件家族不同，向导里版本号会不同
> （Logos 系 `DRM Based Simple Dual Port RAM (1.6)`、`DRM Based ROM (1.5)`；
> Logos-2 是 `(1.7)` / `(1.5)`，且多一个 `DRM Resource Type / CAS_MODE` 选项）。
> **端口名和配置项完全一样**，下面的配置两种系列通用。

---

## 1. 操作步骤（PDS）

1. 工具栏点 **IP** 图标（或菜单 Project → IP Compiler）→ 弹出 `New IP` 目录树。
2. 选 `Module / Memory / DRM / DRM Based Simple Dual Port RAM`，
   **Instance name 填 `bram_dram_ip`**（本目录的 `bram_dram.v` 就是按这个名字例化的），
   点 `Customise` 进入配置页。
3. 按第 2 节的表格填 → `Generate` → 询问 “是否加入工程” 选 Yes。
   生成完 PDS 会**自动弹出例化模板**，端口名以该模板为准。
4. 重复 2~3，选 `DRM Based ROM`，Instance name 填 **`irom_bram_ip`**，按要求配置。
5. 把本目录的 `bram_dram.v`、`irom_bram.v` 加进工程（它们是包装层）。
   **不要再把 Vivado 生成的 `bram_dram` / `irom_bram` 模型加进 PDS 工程**（模块重名）。

---

## 2. 配置字段对照表

### 2.1 DRAM（`bram_dram_ip`，DRM Based Simple Dual Port RAM）

| Vivado Block Memory Generator 里的设置 | PDS IP 配置界面里的字段 | 填什么 |
|---|---|---|
| Memory Type = Simple Dual Port RAM | 由所选 IP 名决定 | — |
| Port A Width = 32，Port A Depth = 65536 | `Write Port` → **Data Width** / **Address Width** | `32` / `16`（2^16 = 65536） |
| Port B Width = 32，Port B Depth = 65536 | 勾选 **Write/Read Port Use Same Data Width** 后自动同步；也可手填 `Read Port` = `32` / `16` | 勾上 |
| Write Enable = **Byte Write Enable**，Byte Size = 8 bit | **Enable Byte Write** = 勾选；**Byte Size** = `8`；**Byte Numbers** = `4` | 生成 `wr_byte_en[3:0]` |
| Port A / Port B Enable = Use ENA / ENB Pin | 写口用 `wr_en`；读口勾 **Enable rd_clk_en Signal**，用 `rd_clk_en` 接 Vivado 的 `enb` | 见 3 的端口表 |
| Operating Mode（Port B）= Write First | 伪双口没有模式选项（行为固定，见第 5 节 d） | — |
| 未使用输出寄存器（读延迟 1 拍） | **Enable Output Register** = **不勾**；**Enable rd_oce Signal** = 不勾 | 关键！ |
| Load Init File = `dram.coe`（如果要用它预置测试数据） | **Enable Init** = 勾；**Init File** = `dram.dat`；**Initial Data Format Type** = `HEX` | 用 `coe2dat.py` 转 |
| 无复位 | `Reset type` = `ASYNC`（或 `Sync_Internally`）；`wr_rst`/`rd_rst` 在包装层接 `1'b0` | — |
| Enable Low Power | **Enable Low Power Mode** = 不勾 | — |
| — | **DRM Resource Type**（Logos-2 上是 CAS_MODE 18K/36K/64K） | 保持默认，界面会显示实际用量 |
| — | **Enable wr_clk_en / wr_addr_strobe / rd_addr_strobe Signal** | 都**不勾**（原设计用不到，少接几根线） |

界面右上角的 `DRM Resource Usage` 会直接写：
`The total used DRM18K is X` / `The total DRM18K is Y` —— 这是判断放不放得下的最直接依据，见第 5 节 b。

### 2.2 IROM（`irom_bram_ip`，DRM Based ROM）

| Vivado 里的设置 | PDS 字段 | 填什么 |
|---|---|---|
| Width = 32，Depth = 4096 | **Data Width** / **Address Width** | `32` / `12` |
| Load Init File = `irom.coe` | **Init Enable** = 勾（ROM 默认就是勾上的，不可取消）；**Init File** = `irom.dat`；**Initial Data Format Type** = `HEX` | 用 `coe2dat.py` 转 |
| 未使用输出寄存器 | **Enable Output Register** / **Enable rd_oce Signal** 都不勾 | 关键！ |
| 无复位 | **Reset Type** = `ASYNC`，`rst` 在包装层接 `1'b0` | — |
| — | **Enable clk_en Signal** / **Enable Address Strobe Signal** / **Enable Low Power Mode** | 都不勾 |

---

## 3. 端口对照表（包装层已经接好，供你核对）

**DRAM**

| Vivado `bram_dram` | PDS `bram_dram_ip` |
|---|---|
| `clka` | `wr_clk` |
| `ena`（恒 1） | 参与 `wr_en`：`wr_en = ena & (\|wea)` |
| `wea[3:0]` | `wr_byte_en[3:0]` |
| `addra[15:0]` | `wr_addr[15:0]` |
| `dina[31:0]` | `wr_data[31:0]` |
| `clkb` | `rd_clk` |
| `enb`（恒 1） | `rd_clk_en` |
| `addrb[15:0]` | `rd_addr[15:0]` |
| `doutb[31:0]` | `rd_data[31:0]` |
| —（Vivado BRAM 无复位） | `wr_rst` / `rd_rst` 接 `1'b0` |

**IROM**

| Vivado `irom_bram` | PDS `irom_bram_ip` |
|---|---|
| `clka` | `clk` |
| `addra[11:0]` | `addr[11:0]` |
| `douta[31:0]` | `rd_data[31:0]` |
| — | `rst` 接 `1'b0` |

**读延迟都是 1 拍**（无输出寄存器），和 Vivado 的 BRAM 一致，所以
`dram_driver.sv` 里 “B 口 latency-1、已内部打拍” 的假设、以及 CPU 侧的提前读时序都不用改。

---

## 4. 初始化文件：PDS 只认 `.dat`

PDS 的 Init File 必须是 `*.dat`（界面代码里写死了 `string match "*.dat"`），
内容 = **一行一个数据**，二进制或十六进制（十六进制时每行 = `DATA_WIDTH/4` 个字符）。
Vivado 的 `.coe` 长这样：

```
memory_initialization_radix=16;
memory_initialization_vector=
00108117,
05010113,
...
```

用本目录的 `coe2dat.py` 转换（纯 Python，无需装包）：

```powershell
# IROM：4096 深 × 32bit，hex
python fpga\pds\coe2dat.py .workbuddy\分区赛测试demo\withMext\irom.coe `
       -o fpga\pds\irom.dat --width 32 --depth 4096 --format hex

# DRAM：65536 深 × 32bit（需要预置数据时才用）
python fpga\pds\coe2dat.py .workbuddy\分区赛测试demo\withMext\dram.coe `
       -o fpga\pds\dram.dat --width 32 --depth 65536 --format hex

# CoreMark 程序（imem.hex，已经是纯 hex 文本，一行一个 32bit 字）
python fpga\pds\coe2dat.py tests\coremark\build\imem.hex `
       -o fpga\pds\imem.dat --width 32 --depth 8192 --format hex
```

> Vivado 里的路径 `e:/FPGA/github/RISCV/cimu/withMext_cimu/irom.coe` 在本机不存在，
> 同名工程实际是 `clmul\withMext_clmul\irom.coe`（3252 个字，≤4096，装得下），
> 已按它转好本目录的 `irom_clmul.dat`。若你手上那份 `cimu` 确实存在，重新跑一次上面的命令即可。

转出来的 `irom.dat` / `dram.dat` / `irom_clmul.dat` 已经放在本目录，可以直接在 IP 向导里选。
`--depth` 是**补齐**到多少行（不足的填 0）；`--format bin` 可输出二进制格式（对应 IP 里选 `BIN`）。
Vivado 的 `Fill Remaining Memory Locations` 在 PDS 里**没有对应选项**，所以靠 `--depth` 把文件
补齐到整个深度（IROM 补 4096 行、DRAM 补 65536 行）最稳妥。

---

## 5. 容易踩的坑

**a. `Enable Output Register` 绝对不能勾。**
勾了读数据再晚一拍（延迟 2 拍），会直接打破 CPU 里 “IROM/DRAM 读延迟 1 拍” 的取指与
提前读（`perip_raddr` / `l0_cache` / `store_buffer`）时序假设。

**b. 先确认 DRM 放得下。**
65536 × 32bit = 2 Mbit ≈ **114 个 DRM18K**。在 IP 界面右上角 `DRM Resource Usage` 里看
`The total used DRM18K is X` 与 `The total DRM18K is Y`；若 X 接近/超过 Y，
必须缩小 DRAM 深度，并同步改：
`perip_bridge.sv` 的 `DRAM_ADDR_START/END`、`dram_driver.sv` 的地址位宽（`perip_addr[17:2]`）。
例如缩到 16384 深（64KB）→ 只要 29 个 DRM18K，区域改成 `256KB → 64KB`。

**c. 跑 CoreMark 时 IROM 要加深。**
现有 `irom_bram` 是 12 位地址 = 4096 字 = 16KB，而 `tests/coremark/build/imem.hex` 有
**5344 个字**（≈21KB），会装不下。做法：IP 里 `Address Width` 改 `13`（8192 深），
同时把 `student_top.sv` 的 `assign inst_addr = pc[13:2]` 改成 `pc[14:2]`（`irom_bram` 的
`addra` 位宽随之改为 `[12:0]`）。

**d. 同址读写的行为和 Vivado 不完全一样。**
Vivado 那边能选 Write First / Read First；PDS 的伪双口行为固定：**写的时候读口输出
`rd_addr` 指向地址的数据**。本设计里 CPU 有 `st_conflict` 护栏，禁止“同址同拍提前读”，
所以不受影响；如果你以后去掉这个护栏，需要自己在读路径加一级旁路 mux。

**e. `wr_en` 不要恒接 1。**
PDS 的伪双口 `wr_en=1` 就是写周期。包装层用的是 `wr_en = ena & (|wea)`，
即只有字节使能里真的有 1 时才写，等价于 Vivado 的 `wea != 0`。

**f. 复位。**
包装层把 `wr_rst`/`rd_rst`/`rst` 接 `1'b0`（等价 Vivado BRAM 无复位）；
DRM 的复位移位只影响输出寄存器，不影响存储内容。若以后勾了 `Enable rd_oce Signal` 或
输出寄存器，就必须接真实复位，否则流水寄存器上电状态不确定。

**g. IP 目录和生成物。**
`Generate` 成功后 PDS 会把 IP 的 `.v`（以及仿真模型）放到工程的 IP 目录并自动加入工程；
这些文件不要手工改，改配置就回到 IP 向导里 `Re-customize`。

**h. 也可以不用 IP，直接用行为级描述让 ADS 推断 DRM。**
如果只想先跑通、不想接 PDS 的 IP 端口，可以写标准可推断写法（综合器会自动映射到 DRM）：

```verilog
reg [31:0] mem [0:65535];
reg [31:0] doutb_r;
always @(posedge clkb) doutb_r <= mem[addrb];          // 读口：1 拍延迟
always @(posedge clka) begin                           // 写口：字节使能
    if (wea[0]) mem[addra][ 7:  0] <= dina[ 7:  0];
    if (wea[1]) mem[addra][15:  8] <= dina[15:  8];
    if (wea[2]) mem[addra][23: 16] <= dina[23: 16];
    if (wea[3]) mem[addra][31: 24] <= dina[31: 24];
end
assign doutb = doutb_r;
```

缺点：字节写会让综合器插入读-改-写逻辑、时序和资源不如 IP 可控；
正式上板建议还是走 IP 路线。

---

## 6. PLL（时钟）移植

Vivado 里是 **Clocking Wizard (6.0)**，PDS 里对应 **Module → PLL → `PLL`**
（Logos 家族是 `ipml_pll`，Logos-2 是 `ipm2l_pll`）。向导里 Instance name 填 **`pll_ip`**。

### 6.1 先看硬约束（IP 自带的算法脚本 `createDivideParam.tcl`）

| 项 | 范围 |
|---|---|
| 输入 clkin1 | **5 ~ 625 MHz** |
| PFD（clkin1 / IDIV） | **5 ~ 320 MHz** |
| **VCO（clkin1 × FDIV / IDIV）** | **600 ~ 1250 MHz** |
| 每路输出 clkoutN | ≤ 625 MHz |
| IDIV / FDIV / ODIVn | 1 ~ 512 |

> Vivado 那份配置的 VCO 是 **1800 MHz**（200 MHz × MULT 9），**已经超过 Pango Logos PLL 的 1250 MHz 上限**，
> 所以分频比必须重算，不能照抄 MULT=9 / DIVIDE=36 / DIVIDE=7。

### 6.2 频率方案（输入 200 MHz，已按上面约束穷举校验）

| 方案 | clk_out1 | clk_out2（CPU） | IDIV | FDIV | ODIV0 | ODIV1 | VCO / PFD | 说明 |
|---|---|---|---|---|---|---|---|---|
| **A（推荐）** | **50.0000** | **262.5000** | 4 | 21 | 21 | 4 | 1050 / 50 MHz | 50M 精确（UART 不用改），CPU 比 Vivado 高 2.1% |
| B | 48.9796 | **257.1429** | 7 | 36 | 21 | 4 | 1028.57 / 28.57 MHz | CPU 与 Vivado 完全一致；50M 偏 −1.02%，UART 的 `CLK_FREQ` 要改成 `48979592` |
| C | **50.0000** | **250.0000** | 1 | 5 | 20 | 4 | 1000 / 200 MHz | 分频比最漂亮，CPU 比 Vivado 低 2.8% |

**A 和 B 不可能同时精确**：要同时命中 50.000 与 1800/7=257.142857，VCO 必须是 1800 的整数倍（=1800、3600…），
全部超出 600~1250 的 VCO 范围。所以要么牺牲 CPU 频率（方案 A），要么牺牲 50M（方案 B），
要么用**两个 PLL**（PGL50H 有多个 PLL 资源）：一个出精确 50M，一个出 257.142857M（IDIV=7/FDIV=36/ODIV=1）。

### 6.3 PDS PLL 配置界面怎么填

**Basic 页**：

| 字段（PDS 原文） | 填什么 |
|---|---|
| `Input Clock clkin1 Frequency :` | `200`（MHz，支持 4 位小数） |
| `[x] Enable clkout0` + `Desired Frequency:` | `50`（右侧 `Actual Frequency:` 自动显示实际值） |
| `[x] Enable clkout1` + `Desired Frequency:` | `262.5`（或方案 B/C 的值） |
| `Desired Phase Shift:` / Duty Cycle | 都留 `0` / `50` |
| `[x] Show Internal Settings of PLL` | 勾上，用来核对 `VCO Clock Frequency(MHz)` 与 IDIV/FDIV/ODIV0..4 |
| `[ ] Enable Port pll_rst` | 不勾（勾了要额外接复位） |
| `[ ] Enable Port pll_pwd`、`Enable clkin Dynamic Select` | 不勾 |
| `Create a dedicated pin 'clkout0_2pad' to pad` | 不勾 |
| `Enable clkoutN Bypass` / `Enable Output Divider Cascade` | 不勾 |

**Advanced 页**：可以直接手填 IDIV / FDIV / ODIV0..4（对应方案 A/B/C 表格里的数字），
其余动态重配（Dynamic Phase/Loop、dyn_* 端口）全部不勾。

### 6.4 差分时钟输入

PDS 的 PLL IP **只有单端输入 `clkin1`**，Vivado 那种 `clk_in1_p / clk_in1_n` 差分对要自己加输入缓冲：

```verilog
GTP_INBUFDS u_clk_in1_ibufds (.O(clk_in1), .I(clk_in1_p), .IB(clk_in1_n));
```

`fpga/pds/pll.v` 已经把这一步和端口改名都做好了，`top.sv` 不用改。
另外记得在 `.fdc` 里把 `i_sys_clk_p/i_sys_clk_n` 声明为**差分时钟输入对**，
否则 PDS 会把两个脚当普通 IO。如果板上那个 200 MHz 是单端晶振，删掉 `GTP_INBUFDS` 直接接 `clkin1`。

### 6.5 端口对照

| Vivado `pll` | PDS `pll_ip` |
|---|---|
| `clk_in1_p` / `clk_in1_n` | 无（用 `GTP_INBUFDS` 转成单端后接 `clkin1`） |
| `clk_out1` | `clkout0` |
| `clk_out2` | `clkout1` |
| `locked` | `pll_lock` |
| （未接） | `pll_rst` / `pll_pwd` / `clkin2` / `clkfb`（勾了才有，建议都不勾） |

PLL 输出一般由布线器自动走全局时钟网络，先不要手加 BUFG；若综合/布线报“时钟未走全局网络”，
再补一个 `GTP_CLKBUFG`。

---

### 6.6 当前实际配置与「改主频」操作（2026-09-30 更新）

**实际跑起来的配置**（不是 §6.2 表里的 A/B，是 PDS 自己选的等价分频）：

| 参数（`ipcore/pll/pll.v` 里的 localparam） | 值 | 结果 |
|---|---|---|
| `STATIC_RATIOI` / `STATIC_RATIOF` | 5 / 25 | VCO = 200 × 25 / 5 = **1000 MHz** |
| `STATIC_RATIO0` / `STATIC_DUTY0` | 20 / 20 | clkout0 = **50 MHz** → UART / twin_controller |
| `STATIC_RATIO1` / `STATIC_DUTY1` | **12 / 12** | clkout1 = **83.3 MHz** → CPU（当前）|
| `VCOCLK_DIV2` | `1'b0` | 别改，改成 1 会让所有输出减半 |

> **降频历史（每次只动一档，各留了备份）**：
> - `STATIC_RATIO1 = 4`（250 MHz）：时序不过 —— 最差路径 10.303 ns（WNS −6.303 ns，
>   11246/27850 端点失败），Fmax ≈ 97 MHz。备份 `*.bak_pre100mhz`。
> - `STATIC_RATIO1 = 10`（100 MHz）：单 seed WNS −0.546（189 端点失败）；
>   多 seed（`-gplace_seed 1 -gplace_times 8 -parallel 4 -mode performance`）挑中
>   **seed_5** → WNS **+0.027**、0 端点失败，P&R 报 `All Constraints Met`；
>   但更严的多 corner `report_timing` 仍报 −0.175 ns（2 条 setup）+ −0.171 ns（1 条 hold）。
>   备份 `*.bak_pre83mhz`。
> - `STATIC_RATIO1 = 12`（83.3 MHz，**当前**）：周期 12 ns，比 10.3 ns 的关键路径
>   多约 1.7 ns —— 两个引擎都应能干净收敛。

**改主频必须三处同步**，缺一处就出错：

1. **`ipcore/pll/pll.v`**：`STATIC_RATIO1 = N`，同时 `STATIC_DUTY1 = N`
   - 本工程里 PLL 是**按普通源码文件登记的**（`.pds` 里是 `(_file "ipcore/pll/pll.v"`，
     而不是 `(_ip ...)`），所以**没有 IP 对话框可以双击**，直接改这个 `.v` 就是正确做法。
   - 顺手把 `ipcore/pll/pll.idf` 的 `STATIC_RATIO1_basicPage` / `STATIC_DUTY1_basicPage`
     改成同一个值，否则将来把 PLL 当 IP 重新生成时会把改动冲掉。
   - 占空比公式（PDS 自带 `arch\vendor\pango\library\operator\clockgeneratefile.txt`）：
     `duty_cycle = STATIC_DUTY / (2 × STATIC_RATIO)`，所以 50% ⟺ **DUTY == RATIO**；
     只用**偶数 N**，奇数 N 会被那个整数 `/2` 弄成偏占空。
2. **`fpga/pds/pins.fdc`**：clkout1 那行改成 `-multiply_by {5} -divide_by {N}`
   （本文件主时钟是 200 MHz），文件末尾 `"CPU clock frequency switch"` 段有完整对照表。
   不改 → STA 仍按旧周期算，并报 `DRC-2018: The waveform of clock "clkout1" ...`。
3. **CoreMark**：`build.ps1 -CpuHz <主频Hz> -Iters <对应 ITERS>`
   （约束是 `ITERS × 397215 ≥ 10 × 主频`，即必须跑满 10 秒），然后
   `fpga/pds/mk_imem_dat.ps1` 生成 `.dat`，再在 PDS 里**重新生成 `irom_bram` IP**。
   不改 → 报出来的秒数/成绩差一个频率倍率，成绩无效。

**验证**：重跑 Compile → Synthesize → Device Map → P&R，看
`place_route\top_timing_summary_after_hold_fix.txt` 里 `clkout1 → clkout1` 的 WNS，
再用 Report Timing（多 corner，更严）复核一遍。
**瓶颈始终是同一条锥体**：`spec_ld_waddr` / `spec_ld_lane`（投机读预测地址）那组
寄存器的扇出 —— 单根 net 就走 ~1.8 ns，下游串到 L0 cache / hazard /
`if_id`·`id_ex1` 的时钟使能。K7-325T 那次的最差路径也是它。
想再往上提频率就得治这里（打一拍再分发 / 减小扇出）。

**不用改的**：`top.sv` 里 UART 的 `CLK_FREQ(50000000)` —— UART 与 twin_controller
都挂在 clkout0（50 MHz）域，改 clkout1 碰不到它们。RTL 里也没有任何硬编码 CPU 频率。

## 7. DRM 资源预算（PGL50H 只有 134 个 DRM18K）

报错原文：

```
C: DeviceMap-2003: The total resource of DRM is 134, but there are 144.00 in the design.
E: DRC-0018: The resource of DRM is not enough.
```

账是这么算的（一个 DRM18K = 18432 bit；带字节写的 32bit 口占 512×36 模式 → 每块 512 字）：

| 用途 | 容量 | 占 DRM18K |
|---|---|---|
| DRAM（原 256KB = 65536 字 × 32bit，带字节写） | 2 Mbit | **128** |
| IROM ×2（双发取指，两份 4096 字 × 32bit） | 2 × 128 Kbit | **16** |
| **合计** | | **144 > 134** |

**DRAM 深度是唯一的杠杆**：换 9/18/36 位模式都省不下来（32bit 数据 + 字节使能至少要 36 位宽的口，
每块仍是 512 字），所以只能缩深度，或者换 DRM 更多的器件。

### 现状（2026-09-20 起）：已采用方案 A —— DRAM 128KB + IROM 8192×2

| 用途 | 配置 | 占 DRM18K |
|---|---|---|
| DRAM（`bram_dram`） | 128KB = 32768 字 × 32bit，带字节写（**Address Width 15**） | **64** |
| IROM（`irom_bram` ×2，双发取指两份） | 8192 字 × 32bit = 32KB（**Address Width 13**），装得下 CoreMark 的 5344 条指令 | **32** |
| **合计** | | **96 / 134**（余 38 块） |

RTL 侧已改好（逐处清单 + 行号见 `plan_irom_resize_review.md` §0），**PDS 里还要做两步**：

1. **IP 重新生成**：`bram_dram` → Write/Read Address Width **16 → 15**；
   `irom_bram` → Address Width **12 → 13**，`Init File` 选 `imem_coremark.dat`，`Initial Data Format Type` = **HEX**。
2. **CPU 取指窗口已从 16KB 扩到 32KB**（`myCPU.sv`：`fq_pci`/`fq_ptgti` 13 位、`head_pc`/`head_ptgt`/`next_ptgt` 前缀 17 位、BTB 表项 15 位）
   —— 这是微架构改动，**必须重新跑 `bash sim/run_riscv.sh`（45 例）与 `tb_student`**，并补一条跨 `0x4000` 的定向用例。

⚠️ **未决事项（影响上板）**：CoreMark 现有二进制是按 `pc=0x0000_0000` + DRAM 256KB 链接的
（`imem.hex` 第 1 条 `auipc gp,0x80101`、第 3 条 `auipc sp,0x80140` 反证），与 CPU 复位 PC `0x8000_0000`
及新的 128KB DRAM 都不符 → **重新编译前必须先把 `link.ld` 的 `IROM ORIGIN` 改成 `0x80000000`、
`DRAM LENGTH` 改成 `128K`**。详见 `plan_irom_resize_review.md` §3.4。

**回退方式**：`powershell -File fpga\pds\backup_pre_irom_resize\restore.ps1`（复原 7 个源文件），
再在 PDS 里把两个 IP 的地址位宽改回 **16 / 12**。

### 其它备选（未采用）

**方案 B：换成 DRM 更多的器件** —— 例如 Logos2 的 PG2L100H，144 块能放下、RTL 一行不用改，
但工程要按新器件重建（IP 换 ipm2l 系列、引脚重配）。

**方案 C：把 IROM 从 DRM 挪到 LUTRAM** —— 两份 IROM 共 16 块，挪走可腾出 16 块
（144-16 = 128 ≤ 134，刚好够）。但要吃掉约 4~6K LUT，且需确认 `Distributed ROM` IP 的深度上限。

---

## 8. 本目录文件

> ⚠️ **这三个包装层（`bram_dram.v` / `irom_bram.v` / `pll.v`）只适用于"保持 Vivado 端口名不动"的方案。**
> 如果你在 PDS 里生成 IP 时把 Instance name 直接取成了 `bram_dram` / `irom_bram` / `pll`
> （RISCV_BASEDON_PANGU 工程就是这样），那 RTL 已经按 PDS 端口名改好了，
> **这三个文件一个都不能加进工程**，否则模块重名。
> 要导入工程的是 PDS 自己生成的 `ipcore/<ip名>/<ip名>.v`（PLL 只有这一个文件，`rtl/` 是空的）。

| 文件 | 说明 |
|---|---|
| `bram_dram.v` | DRAM 包装层（可选，见上方警告）：端口与 Vivado 版 `bram_dram` 一致，内部例化 `bram_dram_ip` |
| `irom_bram.v` | IROM 包装层：模块名/端口与 Vivado 版 `irom_bram` 完全一致，内部例化 `irom_bram_ip` |
| `pll.v` | 时钟包装层：模块名/端口与 Vivado 版 `pll` 完全一致，内部 `GTP_INBUFDS` + `pll_ip` |
| `coe2dat.py` | `.coe` / `.hex` → PDS `.dat` 转换器 |
| `irom.dat` | 由 `.workbuddy\分区赛测试demo\withMext\irom.coe` 转出（4096×32，HEX） |
| `irom_clmul.dat` | 由 `E:\FPGA\github\RISCV\clmul\withMext_clmul\irom.coe` 转出（4096×32，HEX，3252 个字有效） |
| `dram.dat` | 由 `...\dram.coe` 转出（65536×32，HEX，含 1234ABCD 等测试数据） |
| `pins.fdc` | **可直接导入工程**的约束文件：只含时钟约束 —— `create_clock`（`i_sys_clk_p`，200 MHz/5 ns）、`create_generated_clock`（`pll_inst.clkout0` 50 MHz ÷20、`pll_inst.clkout1` 83.3 MHz = ×5÷12，当前值，文件末尾有 N=4~16 的对照表）。**没有任何 `define_attribute` / `PAP_IO_LOC`**，所以不会因为脚位名报错 |
| `pins_template.fdc` | **引脚约束模板，未填完前不要加进工程**：76 个端口的 `PAP_IO_LOC` 全是占位符 `{TODO}`。带着 `TODO` 导入会得到 76 条 `E: UserConstraintEditor-0008: ... Package pin TODO can not be placed.`（每个端口一条）。把 `{TODO}` 换成原理图脚位后再导入，或把它的 Io Table 段并入 `pins.fdc` |
| ↑ 时钟部分解决的消息 | `C: SDC-2025: Clock source 'n:i_sys_clk_p' / 'n:pll_inst/clkout0' / 'n:pll_inst/clkout1' need a clock constraint ...`（补上后这两路时钟域才会真正做 setup/hold 检查；`C: STA-3009 ... top\|i_sys_clk_p ... not connected to any clock endpoints` 通常只是说明该输入只进 PLL，补完约束后不必强行消除） |

### 需要配引脚的端口清单（顶层模块 `top`）

| 分组 | 端口 | 引脚数 | 方向 | 备注 |
|---|---|---|---|---|
| 系统时钟 | `i_sys_clk_p` / `i_sys_clk_n` | 2（1 对） | 输入 | 200 MHz 差分，`create_clock -period 5`，LVDS |
| 串口 | `i_uart_rx` / `o_uart_tx` | 2 | 1 入 1 出 | 9600 波特 |
| LED | `virtual_led[31:0]` | 32 | 输出 | |
| 数码管 | `virtual_seg[39:0]` | 40 | 输出 | bit7/17/27/37 在 `perip_bridge.sv` 里恒 0（小数点） |
| | **合计** | **76** | | |

⚠️ 仓库里那份 Vivado 的 `digital_twin.xdc` 是给 **xc7k325tffg900-2（Xilinx Kintex-7）** 的，
脚位编号（AD12/AK30/B27…）**不能**用于 PGL50H-FBG484，必须按 Pango 开发板原理图的管脚表重填。

RISCV_BASEDON_PANGU 工程的实际做法是**不用包装层**：IP 向导里 Instance name 就填 `bram_dram` /
`irom_bram` / `pll`，直接改 RTL 的例化端口（`rtl/perip/dram_driver.sv` 用 `wr_*`/`rd_*`，
`rtl/perip/student_top.sv` 用 `clk`/`rst`/`addr`/`rd_data`，`rtl/perip/top.sv` 用
`GTP_INBUFDS` + `clkin1`/`clkout0`/`clkout1`/`pll_lock`），这样工程里只有一份模块定义。

---

## 9. 开发板适配：盘古50K / MES50HP（PGL50H-FBG484-6）

> 2026-10-03 加。**本节取代上面第 8 节末尾那张 76 端口的表**（那是移植前按 Kintex-7 竞赛板写的）。
> 脚位全部来自开发板资料里**厂商 demo 自带的约束文件**，逐个核对过。

### 9.1 板子资源和原设计的差异（必须先解决，否则综合出来也跑不了）

| 项 | 原设计（Vivado / Kintex-7 竞赛板） | 盘古50K（MES50HP） | 处理 |
|---|---|---|---|
| 主时钟 | **200 MHz 差分对**（`i_sys_clk_p/n` + `GTP_INBUFDS`） | **50 MHz 单端**（`P20`） | 删掉 IBUFDS，`top.sv` 直接收 `clk_50m` |
| LED | 32 个 | **8 个** | `top.sv` 只引出 `led[7:0]` |
| 数码管 | 40 位（4 位 × 7 段 + 位选） | **没有** | `virtual_seg` 悬空，综合时剪掉 |
| 按键 | 64 位拨码 + 8 键 | 7 个按键，无拨码 | 本设计按键/拨码都来自 `twin_controller`，不受影响 |
| 串口 | 有 | 有（板上 USB-UART） | 9600-8-N-1 |

> **板上没有 200 MHz 差分时钟**：所有厂商 demo 都用 `P20` 的 50 MHz 单端晶振喂 PLL，
> 且 demo 的 PLL IP 里都写着 `CLKIN_FREQ = 50.0`（例：`12_ADDA_LOOP\ipcore\pll\pll.v`、
> `18_oled_test_h_v3\ipcore\PLL\PLL.v`）。原来那套差分输入在这块板子上物理上就不成立。

### 9.2 脚位表（已写进 `pins.fdc`）

| 信号 | 脚位 | 说明 |
|---|---|---|
| `clk_50m` | **P20** | 50 MHz 单端晶振，LVCMOS33 |
| `i_uart_rx` | **R8** | 板上 USB-UART → FPGA |
| `o_uart_tx` | **R9** | FPGA → 板上 USB-UART |
| `led[7]`…`led[0]` | **F8 F7 A5 C5 A3 B3 A2 B2** | 8 个用户 LED |
| （参考）按键 `key[0..6]` | K18 L15 J17 K16 J16 J19 H20 | 本设计不用：复位取自 `pll_lock` |

来源：`<板卡资料>\2_Demo\` 下的 `04_uart_test.rar`（→ `uart_test.fdc`）、
`01_led_test.rar`（→ `led_test.fdc`）、`19_beep_test\prj\source\beep_test.fdc`。

### 9.3 改完的时钟链

```
P20 50MHz 单端 ---> PLL(clkin1)  CLKIN=50, IDIV=1, FDIV=20  -> VCO = 1000 MHz
                        RATIO0=20 -> clkout0 = 50.00 MHz  -> UART + twin_controller
                        RATIO1=12 -> clkout1 = 83.33 MHz  -> CPU
```

- **CPU 频率仍是 83.33 MHz**，所以 CoreMark 的 `-CpuHz 83333333 -Iters 2200` 不用改。
- `pins.fdc` 对应写法：`create_clock -period {20}`（50 MHz）、clkout0 `-divide_by {1}`、
  clkout1 `-multiply_by {5} -divide_by {3}`（50 × 5/3）。
- 本次改过的文件：`rtl/perip/top.sv`、`fpga/pds/pins.fdc`、
  PDS 工程里的 `ipcore/pll/pll.v` 与 `pll.idf`（备份 `*.bak_pre50mhz`；
  工作区里的旧版备份在 `_backup_pre_board_pins\`）。
- `fpga/pds/pins_template.fdc`（76 个 `{TODO}` 占位）**已经没用了，不要导入**
  —— 真正的脚位现在都在 `pins.fdc` 里。

### 9.4 还没做的一步：CoreMark 的串口输出通路

CoreMark 的 printf 写的是**魔法地址** `0xF000_0000` / `0xF000_0004`，这个译码目前
**只在仿真台** `sim/tb/tb_myCPU/tb_myCPU.sv` 里；板上 `perip_bridge.sv` 只译码
DRAM + `0x8020_00x0` 那几个 MMIO，写 `0xF000_0000` 会被丢掉。

所以**现在上板跑 CoreMark，串口不会出任何东西**。要补三处：
1. `perip_bridge.sv`：译码 `0xF000_0000`（写字符）/ `0xF000_0004`（结束标志）/
   `0xF000_0008`（读：发送忙），CPU 时钟域 → 50 MHz 域做一个握手（字节先锁存、翻转请求）。
2. `student_top.sv` / `top.sv`：把 `{tx_valid, tx_byte, tx_busy, done}` 引到 UART，
   与 `twin_controller` 的 TX 复用（跑 CoreMark 时别开数字孪生上位机）。
3. `port/syscalls.c`：发字符前先轮询忙位 —— 9600 波特下一个字符要 87 µs，
   而 printf 是每几十个周期写一个字节，不轮询一定丢字符（除非加个大 FIFO）。


---

## 10. 当前开发板适配：盘古50Pro / MES2L50HP（2026-10-10）

### 10.1 板卡资料与器件

实际板卡是 **盘古50Pro**，器件为 **Logos2 / PG2L50H / FBG484 / -6**。
PDS 为 `D:\realsoftwares\PDS_2022.2-SP6.1`，工程为
`E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU\RISCV_BASEDON_PANGU.pds`。
PLL、ROM、SDPRAM 的 `.idf` 均为 Logos2；两个内存 IP 的生成源码引用 `ipm2l_*`。
工程直接引用本仓库 `fpga/pds/pins.fdc`；PLL `.v` 及关联 `.idf` 位于工程的 `ipcore/pll`。

正确资料目录：`E:\download\盘古50Pro开发板配套资料`。

- `3_Hardware/盘古50Pro硬件使用手册.pdf`：印刷页14（PDF15）是 V4/W4 的125MHz差分时钟；
  页33（PDF34）表3-5是UART；页40–41（PDF41–42）表3-9是LED。
- `3_Hardware/MES-2L484-V1.4核心板原理图.pdf`：R5 bank 为1.5V，时钟有 R73=100Ω 外部端接。
- `2_Demo/Demo/01_led_test/led_test.fdc`、`04_uart_test/uart_test.fdc` 交叉确认 UART/LED。
- `07_ddr3_test/07_ddr3_test/ipcore/ddr3_test/pnr/ddr_test.fdc` 的参考时钟同为 V4/W4，
  配置 SSTL15D_I、VCCIO=1.5V；参考设计使用 `GTP_INBUFDS`。

**旧资料中的 P20 50MHz、R8/R9 UART 和旧 LED 球号不适用于此板。**
本板单端晶振是 **Y18 的27MHz**；F6/E6 的另一对125MHz属于 HSST 专用脚。

### 10.2 全部顶层引脚（已写入 pins.fdc）

| 信号 | 脚位 | PDS 标准 / VCCIO |
|---|---|---|
| `clk_125m_p` | V4 | SSTL15D_I / 1.5V |
| `clk_125m_n` | W4 | SSTL15D_I / 1.5V |
| `i_uart_rx` | P14 | LVCMOS33 / 3.3V |
| `o_uart_tx` | K19 | LVCMOS33 / 3.3V |
| `led[0]` → LED1 | F13 | LVCMOS33 / 3.3V |
| `led[1]` → LED2 | F14 | LVCMOS33 / 3.3V |
| `led[2]` → LED3 | E13 | LVCMOS33 / 3.3V |
| `led[3]` → LED4 | E14 | LVCMOS33 / 3.3V |
| `led[4]` → LED5 | E16 | LVCMOS33 / 3.3V |
| `led[5]` → LED6 | D16 | LVCMOS33 / 3.3V |
| `led[6]` → LED7 | F16 | LVCMOS33 / 3.3V |
| `led[7]` → LED8 | E17 | LVCMOS33 / 3.3V |

12个物理脚均固定；8个LED高电平点亮。UART使用板上 **CP2102 USB Type-C**，9600-8-N-1。
输出驱动8mA、慢沿、无上下拉。P14是share pin，PDS提示属于预期。
LED和UART未设置外部 input/output delay，PDS会提示这些端口没有I/O时序约束；
该提示不表示缺少位置约束。UART接收是异步输入，LED用于状态显示。

### 10.3 用户选择的125MHz差分时钟方案

```
V4/W4 125MHz → GTP_INBUFDS（TERM_DIFF=OFF） → PLL
CLKIN=125, IDIV=1, MDIV=1, FDIV=6 → VCO=750MHz
ODIV0=15, DUTY0=15 → UART/twin_controller = 50MHz
ODIV1= 9, DUTY1= 9 → CPU = 83.333333MHz
```

PLL由 PDS `ip_generate.exe -i ipcore/pll/pll.idf -disable-syn` 重生成，0错误、0警告。
FDC主时钟8ns，clkout0×2÷5（20ns），clkout1×2÷3（12ns）。
不对负端另建时钟；关闭内部差分端接，因为板上已有R73。
两路输出频率保持原值，因此 CoreMark `CPU_HZ=83333333 / ITERS=2200` 和 UART `CLK_FREQ=50000000` 保持。

第9.4节所说的CoreMark UART缺失已经修复：`perip_bridge.sv` 的魔法地址译码、
CPU到50MHz域握手和软件忙位轮询均已存在。无需重复实现。

### 10.4 实现与验收

本次新约束已完成 **Compile → Synthesize → Device Map → P&R → Report Timing**。
2026-10-10 21:03 的独立多 corner 报告为 `report_timing/top.rtr`，器件 PG2L50H-FBG484-6。

| 验收项 | 本次结果 |
|---|---|
| 固定引脚 | 12/12；`place_route/top_prr.prt` 全部为 YES |
| DRM | 48.5/85 = 57.06%（48块DRM36K + 1块DRM18K） |
| CPU slow setup `clkout1→clkout1` | **WNS +0.899ns，TNS 0，失败端点0/20555** |
| CPU fast setup | WNS +5.584ns，TNS 0 |
| CPU slow / fast hold | WHS +0.123 / +0.079ns，THS 0 |
| 全部时钟对最小 setup | +0.483ns（slow，clkout0→clkout1） |
| 全部时钟对最小 hold | +0.079ns（fast，clkout1→clkout1） |
| 多 corner 总结 | **All Constraints Met**，setup/hold无违例 |

P&R 使用单种子 **seed=5 / gplace_times=1 / parallel=1 / performance**。
最初8种子并行出现内存分配失败，降低并行度后两轮P&R均成功。
PDS保存时会省略默认值1，因此 `.pds` 中仅显式保留 seed=5 和performance。
时钟报告确认主时钟8ns、UART20ns、CPU12ns；余量为正，当前83.333MHz设置可继续上板验收。
资源报告的DRM百分比向上取整显示58%，上述57.06%为48.5/85的精确比值。

可复现命令：

```powershell
& 'D:\realsoftwares\PDS_2022.2-SP6.1\bin\pds_shell.exe' -project 'E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU\RISCV_BASEDON_PANGU.pds' -run pnr

# 独立多 corner 时序报告；该批处理命令会从Compile重跑依赖阶段
& 'D:\realsoftwares\PDS_2022.2-SP6.1\bin\pds_shell.exe' -project 'E:\FPGA\github\ZiGuang\RISCV_BASEDON_PANGU\RISCV_BASEDON_PANGU.pds' -run report_timing
```

以最新 `device_map/top.pcf` 核对全部引脚、电压及差分输入，以资源报告核对DRM。
本次单种子报告见 `report_timing/top.rtr`；多种子最终结果见
`place_route/multiseed_result.csv` 及最终所选 `place_route/seed_*/top.rtr`。
检查 CPU `clkout1→clkout1` setup WNS、全部时钟对setup/hold和TNS。
旧 `place_route/top_timing_summary_after_hold_fix.txt` 可能未更新，不能据此判断本次结果。
修改前的文件保存为 `*.bak_pre50pro125mhz`。
真实板卡CoreMark运行已通过，结果见下一节；8个LED的实际结束状态尚待用户确认。

### 10.5 真实板卡 CoreMark 结果（2026-10-10）

用户贴出的串口HEX已解码保存为 `coremark_board_2026-10-10.log`。
该记录来自用户实际板卡输出，本代理未直接采集串口。

| 项目 | 结果 |
|---|---|
| 运行类型 | 2K performance run |
| CPU频率 | 83.333333MHz（当前PLL配置） |
| Iterations | 2200 |
| Total ticks | 874277070 |
| Total time | **10.491325秒**，满足至少10秒 |
| CoreMark / Iterations per second | **209.697062** |
| CoreMark/MHz | **2.51636**，按209.697062 / (750/9)计算 |
| seedcrc | 0xe9f5 |
| list / matrix / state CRC | **0xe714 / 0x1fd7 / 0x8e3a**，均通过 |
| crcfinal | 0x33ff |
| 编译器与选项 | GCC15.2.0，-O2 -march=rv32im |
| 内存方式 | STATIC |
| 程序结论 | **Correct operation validated** |

串口显示 `32 4B 20 ...` 表示打开了HEX显示；切换到文本/ASCII即可直接阅读。
按当前RTL，程序结束后8个LED应全亮并保持；用户尚未提供实际LED状态。

### 10.6 CoreMark 报表参数补全（2026-10-10）

本次修改平台移植层和构建脚本，五个核心 C 文件及 coremark.h 未改。
PowerShell 和 Makefile 均通过 `tests/coremark/scripts/gen_build_info.py`，从实际
CFLAGS、LDFLAGS、链接库和 libc 生成 `build/coremark_build_info.h`，不再手写 FLAGS_STR。
Makefile 在参数变动时更新该头文件并触发对象重编；PowerShell 每次重编全部源文件。

新版报表包含完整编译参数；内存位置改为
`STATIC; code=IROM(BRAM), data=DRAM(BRAM); memory/core clock=1:1`。
在原成绩行后补充如下构建信息，输出均在计时结束后：

```text
CPU clock (Hz)   : 83333333
Linker flags     : -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow -nostartfiles -T port/link.ld -Wl,--gc-sections -Wl,-Map=build/coremark.map --specs=nano.specs
Link libraries   : -lc -lgcc -lnosys
C library        : newlib_nano
```

已按 ITERS=2200、CPU_HZ=83333333、newlib_nano 编译成功，未运行新的仿真或上板测试。
IROM 指令 4930 字（19720 字节），初始 DRAM 数据 756 字（3024 字节）。
两份 `.dat` 已更新为无 BOM、LF，分别填充到 8192 和 32768 字。
完整构建参数另存于 `coremark_build_parameters_2026-10-10.txt`。

**PDS 内存 IP 和 bitstream 尚未更新。** 要让新版报表在板上生效：

1. 重新生成 **irom_bram 和 bram_dram**，两份指令/数据初始化内容都需要更新。
2. Compile → Synthesize → Device Map → Place & Route → Generate Bitstream。
3. 下载新 bitstream，再保存实际串口日志。第 10.5 节为旧版镜像的实测基线，不代表新版复测结果。

旧版 ELF、HEX、DAT 和构建产物保存在 `tests/coremark/_backup_pre_build_report_20261010/`。
完整官方运行要求中的另一组验证种子尚待补充，详见 `coremark_source_audit_2026-10-10.md`。

### 10.7 官方 validation 模式与最新性能基线

用户随后已提供完整参数版的上板报表，保存为 `coremark_board_2026-10-10_full_params.log`：
2200 次、874274872 ticks、10.491299 秒、209.697589 CoreMark（约2.51637 CoreMark/MHz），三个 CRC 通过。
第10.6节中“尚未上板”仅描述补全参数时的历史状态。

现已增加 `build.ps1 -RunMode Performance/Validation -BuildDir ...` 和 Makefile 的 `RUN_MODE`、`BUILD`，
采用官方两组种子并固定 TOTAL_DATA_SIZE=2000；核心源码保持未改。
`coremark_official/` 中两组镜像独立保存，导出时校验六个官方源码的哈希。

validation 的 10 次 RTL 仿真已完成，3969339 ticks，seedcrc=18f2、list=e3c1、matrix=0747、state=8d84。
日志在 `coremark_official/validation/simulation_crc_10iters.log`。
仿真时间仅0.039693秒，因此出现 `ERROR! Must execute for at least 10 secs` 和 `Errors detected` 是预期，
本记录只证明新种子的 CRC 正确，不能替代完整上板验证。
4000次上板镜像预计约19秒，最终以真实串口计时为准。

**当前活动两份 DAT 已选择 validation。PDS 内存 IP 和 bitstream 尚未因本次切换更新。**
下一步重生成 **irom_bram 和 bram_dram**，完成PDS构建并下载，收集验证运行日志。
正式验收须时间至少10秒且处于32位计时范围内（小于约51.54秒），CRC通过并显示 `Correct operation validated`。
validation 成功后不打印 `CoreMark 1.0`，这是官方正常行为。

切换前活动 DAT 备份在 `_backup_coremark_selection_20261010_234629_762/`；
切回新 performance 包使用 `select_coremark_image.ps1 -RunMode Performance`，同样需重生成两内存IP及bitstream。
完整操作、期望CRC和重建命令见 [官方运行镜像说明](coremark_official/README.md)。

### 10.8 validation 真实板卡验收完成

用户随后提供完整验证运行日志，保存到 `coremark_official/validation/board_validation.log`。

| 项目 | 结果 |
|---|---|
| 类型 | 2K validation run |
| Iterations / CPU_HZ | 4000 / 83333333 |
| Total ticks | 1588608811 |
| Total time | 19.063306秒，超过10秒且在32位计时范围内 |
| seedcrc | 18f2 |
| list / matrix / state CRC | e3c1 / 0747 / 8d84，均符合官方预期 |
| crcfinal | 5249，随迭代次数变化 |
| 程序结论 | Correct operation validated；没有ERROR |

两组上板运行证据已齐备：performance=2200次、10.491299秒，validation=4000次、19.063306秒。
第10.7节“验证尚待上板”描述的是镜像准备完成时的历史状态；当前已完成验证。
对外性能成绩仍为 **209.697589 CoreMark，约2.51637 CoreMark/MHz**；validation的209.827196不作为性能成绩。
当前活动镜像继续保持validation，本次分析没有切换或重编译软件。
串口日志来自用户粘贴，代理没有直接采集串口，也未重新核对此次PDS实现报告。
