# 全新官方 CoreMark 源码独立重新编译

日期：2026-10-11。用户要求从官方重新clone并编译，观察是否出错。

## 源码获取

官方仓库：<https://github.com/eembc/coremark>。
`git clone --depth 1` 首先因Git配置的127.0.0.1:7890代理未监听而失败；
命令范围内绕过代理后，GitHub Git端点分别遇到Schannel/OpenSSL TLS连接失败。
未修改全局Git配置，未关闭证书验证。

随后从官方codeload下载全新HEAD源码ZIP成功：
<https://codeload.github.com/eembc/coremark/zip/HEAD>。
**本次取得的是官方源码快照，Git clone未成功，不包含Git历史。**

ZIP内Git archive注释记录提交：`1f483d5b8316753a742cbf5590caf5bd0a4e4777`。
ZIP SHA256：`2fb1065f40af2dc7dd533a366c737b219416aab77abd7e4db7a2067a908be4cb`。
源码及与旧源码的逐文件比较保存在 `source_provenance.json`。

官方五个核心C文件及coremark.h直接从解压目录复制到独立构建工作区，未修改内容；
按CRLF转LF比较，与现有 `tests/coremark/src` 的六个文件全部一致。
原仓库完整内容保留在 `official_source/coremark-HEAD/`。

## 编译配置和结果

沿用本项目裸机port（CSR计时、UART、启动代码、链接脚本）与构建脚本副本。
工作区为 `rebuild_workspace/tests/coremark/`，原CoreMark目录没有被覆盖。
GCC=xPack RISC-V 15.2.0，ISA=rv32im_zba_zicsr、ABI=ilp32、O3、newlib_nano、无LTO。
两组均为4000次、CPU_HZ=83333333、TOTAL_DATA_SIZE=2000，分别选择PERFORMANCE_RUN/VALIDATION_RUN。
包含路径与构建目录采用原B2相同相对路径，以便直接比较产物。

| 项目 | Performance | Validation |
|---|---:|---:|
| 构建退出码 | 0 | 0 |
| 编译日志错误/警告诊断 | 0 / 0 | 0 / 0 |
| IROM .text | 21836 B / 5459字 | 21836 B / 5459字 |
| DRAM初始化数据 | 3084 B / 771字 | 3084 B / 771字 |
| ELF与原B2 | 字节完全一致 | 字节完全一致 |
| 指令DAT与原B2 | 字节完全一致 | 字节完全一致 |
| 数据DAT与原B2 | 字节完全一致 | 字节完全一致 |

日志：`performance_build.log`、`validation_build.log`。
比较结果及SHA256：`build_comparison.json`。
独立ELF/HEX/BIN/DAT/map/参数头文件和manifest位于 `packages/performance_long/`、`packages/validation/`。
DAT导出时再次检查全新源码的官方固定版本哈希，两组均通过。
GNU size的text总数含只读数据，不等同于IROM .text；此表采用实际提取的coremark.text.bin大小。

## 结论与范围

重新取得官方源码后，当前B2的编译、链接和镜像导出没有报错，且产物重现原B2文件。
因此未发现现有CoreMark核心源码被修改或本次重新构建出现差异的证据。
这不等于证明编译器在所有输入下没有bug，也不等于新的运行验证。
DIVU指令回归的错误预期仍属于独立的 `tests/unofficial_test_data/rv32um-p-divu.dat`，
本次CoreMark构建不读取或生成它，不能用本次编译定位该旧镜像最初的生成原因。

本次未运行RTL仿真、PDS或上板，未选择活动DAT、修改RTL/IP/FDC。
已有用户提供的B2+新BTB performance/validation上板CRC记录仍保留在 `fpga/pds/coremark_b2/`。
