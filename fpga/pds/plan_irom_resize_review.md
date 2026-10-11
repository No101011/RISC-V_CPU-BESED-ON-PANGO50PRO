# 审查报告 + 执行记录：PGL50H 上给 CoreMark 扩 IROM

日期：2026-09-20　目标器件：**PGL50H-FBG484-6（Logos，DRM18K = 134 块）**
结论一句话：**光把 IROM 从 4096 改成 8192 是不够的** —— 这个 CPU 的取指 PC 窗口被硬编码成 **16KB**，
CoreMark 的 20.9KB 代码跑不过 0x4000 这条线。必须同时动 DRAM 预算、IROM 位宽、CPU 内部 PC 位宽三处。

---

## 0. 执行状态（2026-09-20，已按方案 A 落地）

**决策（用户确认）**：方案 A（DRAM 128KB + IROM 8192×2）｜BTB 保持 2048 行｜**暂不改 link.ld**｜CPU PC 位宽由 agent 改｜改动前先备份｜顺手修"上电全空"初始化 bug。

**备份**：`fpga/pds/backup_pre_irom_resize/`（7 个源文件 + `restore.ps1`，一键复原）
复原命令：`powershell -File fpga\pds\backup_pre_irom_resize\restore.ps1`

| # | 改动 | 文件 | 状态 |
|---|---|---|---|
| 1 | DRAM 窗口 256KB→128KB | `rtl/perip/perip_bridge.sv:42` | ✅ |
| 2 | DRAM 字地址 16→15 位 | `rtl/perip/dram_driver.sv:14,20,54` | ✅ |
| 3 | DRAM 窗口译码 4 处 | `rtl/soc/myCPU.sv:907,954,988,1010` | ✅ |
| 4 | IROM 4096→8192 字（13 位） | `rtl/perip/student_top.sv:44,52,53` | ✅ |
| 5 | CPU PC 窗口 16KB→32KB（`fq_pci`/`fq_ptgti` 13 位、`head_pc`/`head_ptgt`/`next_ptgt` 前缀 17 位、4 处 `[14:2]`） | `rtl/soc/myCPU.sv:253,255,276,278,282,352,353,356,357` | ✅ |
| 6 | BTB 表项 14→15 位（目标 13 位、take 移到位 14、RAS 位 13），索引仍 `pc[13:3]` | `rtl/soc/myCPU.sv:156,157,172,186,187,189,190` | ✅ |
| 7 | **修 bug**：BTB 初始化循环 `bi < 1024` → `bi < 2048`（原来只清一半，仿真上半区是 X） | `rtl/soc/myCPU.sv:160` | ✅ |
| 8 | 仿真模型同步新接口/新尺寸（IROM 13 位/8192 字；DRAM 15 位/32768 字、`wr_*`/`rd_*`） | `sim/models/IROM.v`、`sim/models/bram_dram.v` | ✅ |
| 9 | 测试台 DRAM 范围/镜像同步 | `sim/tb/tb_student/tb_student.v`、`sim/tb/tb_myCPU/tb_myCPU.sv` | ✅ |
| 10 | CoreMark 初始化文件（8192 行，5344 条指令 + 补零） | `fpga/pds/imem_coremark.dat` | ✅ |

**仍未做（需要你在 PDS / 工具链里操作）**：

1. **IP 重新生成**：`bram_dram` → Write/Read Address Width **16 → 15**；`irom_bram` → Address Width **12 → 13**、Init File 选 `imem_coremark.dat`、格式 HEX。
2. **回归仿真**（CPU 动了分支/PC 重建，必须跑）：`bash sim/run_riscv.sh`（45 例）+ `tb_student`；并**新增一条跨 0x4000 的定向用例**（现有测试都在低 16KB，测不出 PC 截断）。
3. **CoreMark 重新链接**（本报告 §3.4 的两个问题，用户说暂不需要，故未动）：
   - 链接基址要改成 `0x80000000`（与 CPU 复位 PC 一致），否则 `gp/sp` 算错；
   - `link.ld` 的 `DRAM LENGTH` 要跟着改成 `128K`（否则新编出来的程序栈顶还在 `0x80140000`，落在不存在的地址上）。
   - ⚠️ **在改这两条之前，不要用当前 `link.ld` 重新编译 CoreMark 上板。**

---

## 1. 事实与证据

| 事实 | 证据（文件:行） |
|---|---|
| 器件只有 134 个 DRM18K | PDS 日志 `C: DeviceMap-2003: The total resource of DRM is 134, but there are 144.00 in the design.` |
| 当前 DRAM = 256KB = 65536 字 × 32bit，带字节写 | `rtl/perip/perip_bridge.sv:41-42`（`0x8010_0000`~`0x8013_FFFF`）、`rtl/perip/dram_driver.sv:14,20`（`perip_addr[17:2]`） |
| 当前 IROM = 4096 字 × 32bit，**两份**（双发取指） | `rtl/perip/student_top.sv:42,51-52`（`logic [11:0] inst_addr`、`pc[13:2]`）、`:76,83`（`Mem_IROM` / `Mem_IROM_B`） |
| CoreMark 程序 = **5344 字 = 20.9KB**（末尾无零填充） | `tests/coremark/build/imem.hex` 共 5344 行，最后一条非零指令在第 5344 行 |
| CPU 复位 PC = **0x8000_0000** | `rtl/core/pc_reg.v`：`pc <= 32'h8000_0000;` |
| CPU 内部 PC/目标索引只有 **12 位（=16KB）** | `rtl/soc/myCPU.sv:251,253`（`fq_pci`/`fq_ptgti` 为 `[11:0]`）`:274,276,280`（`head_pc`/`head_ptgt`/`next_ptgt` 硬编码前缀 `18'b10_0000_0000_0000_0000`）`:350,351,354,355`（`<= fpc_a[13:2]` 等） |
| BTB 也只覆盖 16KB | `rtl/soc/myCPU.sv:154-155`（行宽 14 位）、`:170`（目标只存 `e2_pc_target[13:2]`）、`:180-181`（索引 `pc[13:3]`，2048 行）、`:184-185`（目标重建前缀 `18'b10…`） |
| CoreMark 链接基址是 **0x0000_0000**（与 CPU 的 0x8000_0000 不符） | `imem.hex` 前 3 条：`80101197` = `auipc gp,0x80101`、`29818193` = `addi gp,gp,0x298` → gp = pc + 0x8010_0298，只有 pc=0 才落在 DRAM；`80140117` = `auipc sp,0x80140` → sp = 0x8014_0000（=256KB DRAM 顶）也只有 pc=0 成立 |
| 自带小测试看不出来这个坑 | `tests/my_test_data/R_I_test.hex`、`B_test.hex`、`J_test.hex` 前几条都是 `addi/jal`，**没有 auipc**，与基址无关 |

### DRM18K 换算（每块 18432 bit）

- 32bit 数据 + 字节写使能 → 必须占 512×36 模式 → **每块 512 字**
- ROM 无字节写 → 1024×18 模式，2 块装 1024 字 → **每 1024 字 2 块**
- 即：DRAM 65536 字 = **128 块**；IROM 4096 字 = **8 块/份**；IROM 8192 字 = **16 块/份**
- 现状核对：128 + 8×2 = **144** = 日志里的 144.00 ✅ 模型正确

---

## 2. DRM 预算方案（必须选一个）

| 方案 | DRAM | IROM（两份） | 合计 | 结论 |
|---|---|---|---|---|
| 现状 | 256KB = 128 块 | 4096×2 = 16 块 | 144 | ✗ 超 10 块；且装不下 CoreMark |
| **A（推荐）** | **128KB = 64 块** | **8192×2 = 32 块** | **96 / 134** | ✅ 余 38 块，CoreMark 装得下 |
| B | 256KB = 128 块 | 8192×2 = 32 块 | 160 | ✗ 差 26 块，**不可能** |
| C | 256KB = 128 块 | 8192×1 = 16 块（单份，需改双口） | 144 | ✗ 仍然超 —— **256KB DRAM 与 CoreMark 不能共存** |
| D | 64KB = 32 块 | 8192×2 = 32 块 | 64 / 134 | ✅ 余量大，但 DRAM 只剩 64KB |
| E（可选优化） | 128KB = 64 块 | 8192 单份 **真双口** = 16 块 | 80 / 134 | ✅ 省 16 块，但要把两份 ROM 换成一份 `DRM Based Dual Port RAM`（写口恒 0），RTL 改动比 A 大 |

**推荐 A**：改动最小、CoreMark 装得下、余量足够以后再放 UART FIFO / 调试核等。

---

## 3. 需要修改的清单（逐处，含风险等级）

### 3.1 DRAM 缩到 128KB（中等风险：改了内存映射，**必须重新链接程序**）

| 文件 | 位置 | 改法 |
|---|---|---|
| `rtl/perip/perip_bridge.sv` | `DRAM_ADDR_END` | `32'h8013_FFFF` → `32'h8012_0000`（判据是 `<`，开区间） |
| `rtl/perip/dram_driver.sv` | `dram_addr` 声明与两处切片 | `[15:0]`→`[14:0]`；`perip_addr[17:2]`→`[16:2]`；`perip_raddr[17:2]`→`[16:2]` |
| `rtl/soc/myCPU.sv` | 4 处窗口译码 | `[31:18] == 14'h2004` → `[31:17] == 15'h4008`（`:905` dram_range、`:954` 仿真断言、`:986` spec_base_in_dram、`:1008` e2_sb_range） |
| `tests/coremark/port/link.ld` | `DRAM ... LENGTH` | `256K` → `128K`，栈顶注释 `0x80140000` → `0x80120000` |
| `sim/tb/tb_student/tb_student.v` | 镜像大小 + 2 处范围 | `32768`、`< 32'h8012_0000` |
| `sim/tb/tb_myCPU/tb_myCPU.sv` | `DRAM_WORDS` + `in_dram` 上界 | `32768`、`+ 32'h0002_0000` |
| **PDS 工程** | `bram_dram` IP | Re-customize：Write/Read Address Width **16 → 15**，重新 Generate |

> ⚠️ 这一步此前已做过两次、又被撤回两次。当前仓库是 256KB 状态。

### 3.2 IROM 扩到 8192 字 / 13 位地址（低风险，机械改动）

| 文件 | 位置 | 改法 |
|---|---|---|
| `rtl/perip/student_top.sv` | `:42` | `logic [11:0] inst_addr, inst_addr2;` → `logic [12:0] ...` |
| 同上 | `:51-52` | `pc[13:2]` → `pc[14:2]`（两行） |
| **PDS 工程** | `irom_bram` IP | Re-customize：**Address Width 12 → 13**；`Init File` 选 8192 行的 `.dat`，格式 HEX；重新 Generate |
| 程序数据 | `fpga/pds/` | 用 `coe2dat.py --depth 8192` 重新生成 `imem.dat`（CoreMark 5344 字，8192 深度足够） |

### 3.3 **CPU 取指 PC 窗口 16KB → 32KB（高风险，必须重新仿真）**

不加这一项，3.2 改了也没用：0x4000 以上的指令取回来时，架构 PC（`head_pc`）会被截断成低 16KB 的地址，`auipc`/`jal`/分支目标全错。

| 位置 | 现在 | 改成 |
|---|---|---|
| `myCPU.sv:251,253` | `reg [11:0] fq_pci / fq_ptgti [0:7];` | `reg [12:0] ...` |
| `myCPU.sv:274` | `head_pc = {18'b10…0, fq_pci[fq_hp], 2'b00}` | `{17'b1_0000_0000_0000_0000, fq_pci[fq_hp], 2'b00}` |
| `myCPU.sv:276,280` | 同上（`head_ptgt` / `next_ptgt`） | 同上 |
| `myCPU.sv:350,351,354,355` | `<= fpc_a[13:2]` / `fsucc_a[13:2]` / `in_b_pc[13:2]` / `fsucc_b[13:2]` | `[14:2]`（4 处） |
| `myCPU.sv:154,155` | `reg [13:0] btb_mem_e/o [0:2047];` | `reg [14:0] ...`（目标位宽 12→13） |
| `myCPU.sv:170` | `{2'b10, e2_pc_target[13:2]}` / `{2'b11, 12'd0}` | `{2'b10, e2_pc_target[14:2]}` / `{2'b11, 13'd0}` |
| `myCPU.sv:180-183` | `wire [13:0] btb_row_*/btb_a/btb_b` | `[14:0]` |
| `myCPU.sv:184,185` | `btb_a[12] ? ras : {18'b10…0, btb_a[11:0], 2'b00}` | `btb_a[13] ? ras : {17'b1_0000_0000_0000_0000, btb_a[12:0], 2'b00}` |
| `myCPU.sv:187,188` | `take_a = btb_a[13]` / `take_b = … btb_b[13]` | `btb_a[14]` / `btb_b[14]` |

**BTB 索引是否也要扩？（需要你决定）**
`:173,174,180,181` 用 `pc[13:3]` 索引 2048 行 → 32KB 下高低两半会互相别名。

- **不扩（推荐先这样）**：别名只导致**误预测**（多花几拍），因为 `myCPU.sv:153` 的注释和 EX2 纠正机制保证"表项错了只会付误预测惩罚，不会算错"。风险最小、LUT 不变。
- **扩到 4096 行**（索引改 `pc[14:3]`）：预测更准，但 BTB 存储翻倍（约 +900 LUT，`btb_mem_e/o` 是分布式 RAM）。

**顺带发现的既有 bug（建议一并修）**：`myCPU.sv:158` 的初始化循环 `for (bi = 0; bi < 1024; ...)` 只清了 2048 项里的**一半**，注释却写"上电全空"。FPGA 上电确实为 0，但**仿真时上半区是 X**，可能引起 X 传播。若数组扩到 4096 行，这个上界必须同步改。

### 3.4 CoreMark 的链接基址（**独立问题，不修就上不了板**）

- CPU 复位 PC = `0x8000_0000`，`head_pc`/BTB 目标也都在 `0x8000_0000` 窗口内 → 程序必须**按 0x8000_0000 链接**。
- 但当前 CoreMark 是按 **0x0000_0000** 链接的（`imem.hex` 第 1 条 `auipc gp,0x80101` 反证）→ 上板后 `gp = 0x0010_0298`，全局变量访问全错。
- 两种修法（**必须选一个**）：
  - **(i) 改链接脚本**：`tests/coremark/port/link.ld` 的 `IROM (rx) : ORIGIN = 0x00000000` → `0x80000000`，重新编译。改动小，但要重跑 toolchain。
  - **(ii) 改 CPU 基址**：`pc_reg.v` 复位值 + `head_pc`/`head_ptgt`/`next_ptgt`/`btb_tgt_*` 的前缀都改成 0。会**同时影响他们现有的 riscv-tests 流程**（那套是按 0x8000_0000 跑的），不推荐。
- 另外注意：`imem.hex` 第 3 条 `auipc sp,0x80140` → `sp = 0x8014_0000`，说明这份二进制是按 **256KB DRAM** 链接的；一旦按方案 A 缩到 128KB，**必须重新链接**（否则栈落在不存在的地址上）。

---

## 4. 改动后必须做的验证

1. **Vivado 仿真**：`sim/tb/tb_myCPU`（riscv-tests 全套）—— 确认 PC 位宽改动没有破坏分支/链接。
2. **新增一条跨 16KB 的定向测试**：在 ROM 的 0x4000 之后放一条 `jal`/`auipc`，检查目标地址正确（这是唯一能暴露 PC 截断的用例；现有测试全在低 16KB，测不出来）。
3. **`sim/tb/tb_student`**：DRAM 缩到 128KB 后镜像对账范围要对上。
4. **PDS**：`Compile → Synthesize → Device Map`，日志里 DRM 应变成 **96 / 134**。
5. 上板：串口 9600 看 CoreMark 输出。

---

## 5. 待你确认的四点（确认后我再动手）

1. **DRAM 取 128KB（方案 A）还是 64KB（方案 D）？** —— 128KB 够跑 CoreMark（栈 8K + 堆 16K + 数据），余量 38 块。
2. **BTB 保持 2048 行（接受误预测，零 LUT 增量）还是扩到 4096 行（更准，+约 900 LUT）？**
3. **CoreMark 重新链接基址 0x80000000 —— 你那边 RISC-V 工具链还能用吗？** 能用的话我把 `link.ld` 一起改好（含 DRAM 128K）。
4. **3.3 的 CPU 改动是我来动，还是你自己动/先仿真验证？** 这批改动涉及分支预测与 PC 重建，属于微架构改动，我可以做，但**必须**由你在仿真里回归。
