# 初始化路径与已生成 IP 内容不一致

2026-10-12，用户确认最近的241.807098次/秒validation报告是在选择B2 performance_long两份DAT后生成。
只读核对发现：B2 DAT本身未被覆盖，两个.idf的INIT_FILE也已正确指向B2；
但当前已生成的两个IP仍包含B4 validation的内容。这解释了串口报告中的B4/LTO/validation标识。

## 已确认的证据

| 层次 | 当前内容 |
|---|---|
| B2 performance_long两份DAT | SHA256与B2构建manifest一致，未变成B4 |
| irom_bram.idf / bram_dram.idf | B2 performance_long，修改时间2026-10-11 21:57:17 |
| irom_bram.v:49 | INIT_FILE仍标注coremark_b4/validation/imem_coremark.dat |
| bram_dram.v:78 | INIT_FILE仍标注coremark_b4/validation/dmem_coremark.dat |
| irom_bram_init_param.v | 2026-10-11 21:37:38生成，8192个字全部匹配B4 validation |
| bram_dram_init_param.v | 2026-10-11 21:37:12生成，32768个字全部匹配B4 validation |

audit.py解码生成的288bit INIT块，剔除DRM奇偶位布局，重建全部32bit初始化字；
ROM为每物理9bit的两个4bit字段，RAM为每两个物理9bit的两个8bit字段。
重建结果与B4 validation两份DAT逐字完全一致（差0字），与B2 performance_long分别差7498/748字。
RAM初始化数据还直接包含-O3 -flto、build/b4/validation、-DVALIDATION_RUN=1等完整报告字符串。
当前PDS工程引用这些生成的ipm2l_*源码，且初始化通过init_param.v内联。

这是磁盘生成文件的核对，没有读回板上位流；该内容与用户本轮UART报告一致。
没有修改RTL、IP配置、DAT，也没有运行PDS或下载。

## 处理步骤

1. 在PDS分别重新打开irom_bram、bram_dram的IP配置，确认INIT_FILE为B2 performance_long对应DAT。
2. 对两个内存IP执行生成，使包装.v和rtl/*_init_param.v都更新；只继续Compile不会保证旧生成内容更新。
3. 核对生成的包装.v的INIT_FILE已经为B2，再重新执行Compile→Synthesize→Device Map→P&R→Generate Bitstream并下载新位流。

B2 performance_long对应的串口应出现2K performance run、无-flto、build/b2/performance_long、
seedcrc=e9f5、CRC=e714/1fd7/8e3a，并在有效运行后打印CoreMark 1.0成绩行。

## 保存的文件

audit.json保存输入SHA256、idf/包装路径、完整初始化字比较及嵌入字符串。
两个.idf、两个包装.v、两个init_param.v均已原样保存；imem_decoded.dat/dmem_decoded.dat为解码结果。
audit.py是只读核对脚本，结果文件写在本目录；当前解码规则适用于本工程的4bit ROM和16bit RAM DRM配置。
