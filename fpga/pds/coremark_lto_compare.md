# B3 / B4：当前 RTL 的 LTO 对比镜像

**最终决定（2026-10-11）：用户采用B2 O3 / 无LTO，停止后续B3/B4对比测试。**
B3/B4已各取得validation通过记录，日志及更新后的manifest在对应目录；performance未继续测试。
下文保留构建时说明与操作步骤，B3/B4为历史对比产物。

生成日期：2026-10-11。B3 为 Zba + O2 + LTO，B4 为 Zba + O3 + LTO。
GCC 15.2.0，ISA 均为 `rv32im_zba_zicsr`、ILP32、medlow、newlib_nano。
两套上板 performance / validation 均为 **4000 次、83333333 Hz、2000 字节**。
CPU RTL 沿用当前两位方向计数器 + PC[14] 标签的 BTB 实现。

## 文件

| 配置 | 性能目录 | 性能 .text | 初始化数据 | 验证目录 | 验证 .text |
|---|---|---:|---:|---|---:|
| B3：O2 + LTO | `coremark_b3/performance_long/` | 16948 B | 3128 B | `coremark_b3/validation/` | 16944 B |
| B4：O3 + LTO | `coremark_b4/performance_long/` | 30060 B | 3136 B | `coremark_b4/validation/` | 30056 B |

两者均能放入 32768 B IROM；B4 性能版余量为 2708 B。
代码大小不能用于推断运行成绩。`riscv-none-elf-size` 的 text 汇总含 DRAM 中的只读数据，
因此判断 IROM 容量时应看 ELF `.text` / `coremark.text.bin`，不能直接看该工具的 text 汇总。

每套另有 `sim_performance/`、`sim_validation/`：10 次、100 MHz，供后续短仿真使用。
每组包含成对 DAT、ELF、HEX、BIN、map、反汇编、参数头文件、构建日志和 SHA256 manifest。
指令 DAT 为 8192 个 32 位字，以 NOP 补齐；数据 DAT 为 32768 字，以零补齐。
两份 DAT 均 ASCII、LF、无 BOM。

## 上板测试：推荐按目录直接选择 IP 初值

先测 B3，再测 B4。B3 性能版对应两个绝对路径：

```text
E:\FPGA\github\RISCV\RISCV_CPU_BaseOn_Pangu\fpga\pds\coremark_b3\performance_long\imem_coremark.dat
E:\FPGA\github\RISCV\RISCV_CPU_BaseOn_Pangu\fpga\pds\coremark_b3\performance_long\dmem_coremark.dat
```

1. 在 PDS 将 `irom_bram` 的 INIT_FILE 设为第一条路径，将 `bram_dram` 设为第二条路径。
2. 重新生成 **两个内存 IP**。
3. Compile → Synthesize → Device Map → P&R → Report Timing → Generate Bitstream。
4. 核对当前实现的 setup/hold，下载，UART 使用 9600-8-N-1 文本接收。
5. 保存完整串口输出，确认 flags 同时包含 `-O2 -flto`，Iterations=4000，CPU clock=83333333。
6. B4 将两个路径中的 `coremark_b3` 一起改为 `coremark_b4`；串口 flags 应为 `-O3 -flto`。
7. 验证模式将两个路径的 `performance_long` 一起改为 `validation`，重新生成并下载。

如果 IP 的 INIT_FILE 已固定指向 `fpga/pds/` 根目录的活动 DAT，也可以使用选择脚本。
在仓库根目录执行 B3 性能选择：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/select_coremark_image.ps1 -RunMode Performance -PackageDir fpga/pds/coremark_b3/performance_long
```

B4 将 b3 改为 b4；验证模式同时改为 `-RunMode Validation` 和相应的 `validation` 目录。
脚本会校验哈希、备份原活动 DAT 并成对复制；**它不会改变 IP 已保存的 INIT_FILE 路径**。
无论采用哪一种选择方式，都要重新生成两个内存 IP 和位流。

## CRC 与比较方法

| 模式 | seedcrc | list / matrix / state | 4000 次 crcfinal 参考 |
|---|---|---|---|
| performance | e9f5 | e714 / 1fd7 / 8e3a | 65c5 |
| validation | 18f2 | e3c1 / 0747 / 8d84 | 5249 |

正式运行应至少 10 秒且显示 `Correct operation validated`；validation 正常不打印 `CoreMark 1.0` 行。
4000 次是否达到 10 秒以串口实际时间为准。

当前新 BTB + B2 O3 / 无 LTO 的上板基线：
4000 次、1402750453 ticks、16.833006 秒、237.628390 CoreMark、2.851541 CoreMark/MHz。
对比两组使用相同 RTL、频率和次数的结果：

```text
周期/迭代 = Total ticks / 4000
CoreMark/MHz = Iterations/Sec / 83.333333
相对 B2 的吞吐量提升 = 1402750453 / 新 Total ticks - 1
```

新 BTB 下的 B1 O2 / 无 LTO 4000 次可使用现有 `coremark_b1/performance_long/`。
此前 B1 的 210.547680 成绩使用旧 BTB、2200 次，不是当前硬件的 O2 对照结果。

## 构建与移植层处理

`tests/coremark/build.ps1` 增加可选 `-Lto`，默认仍关闭。
开启时在编译和链接同时传入 `-O2/-O3 -flto`，并定义 `COREMARK_LTO=1`。
所有项目 C 源文件使用相同编译参数；newlib_nano 等工具链库使用原有预编译版本。

首轮 LTO 暴露了移植层 `align_mem` 缺少声明的问题；现在在 `core_portme.h` 补齐
`ee_u8 *align_mem(void *memblock)`，实现签名同步，保留原来的 8 字节对齐计算。
只改项目移植层，没有改六个官方核心文件。

开启 LTO 时 `start_time/stop_time` 使用 GCC `noipa` 属性，保留计时边界与仿真定位符号。
读取 mcycle 的 asm 使用 `volatile` 和 `memory` clobber；其目的是避免内存访问跨越采样点重排。
两套包的实际编译/链接参数均进入串口报表，manifest 记录构建时 CPU 顶层和移植层的哈希。

最终八组编译和链接均退出码 0、无编译器 warning/error；官方源码哈希、DAT 格式和
ELF/HEX 对应关系及计时采样符号已在导出时检查。
**本次仅编译、打包和静态核对，没有运行 RTL 仿真、PDS 或上板，CRC 运行验证待完成。**

一次重建 B3 + B4：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File fpga/pds/build_coremark_lto.ps1 -Python C:/Users/ASUS/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
```

支持 `-Variant B3` 或 `-Variant B4` 只重建一组，也支持 `-Toolchain`、`-Python`。
构建脚本输出独立目录，不自动选择根目录活动 DAT，不自动修改 PDS IP。
