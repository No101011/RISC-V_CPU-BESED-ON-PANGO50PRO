# B2 重新生成与旧 DAT 清理

## 后续完整清理请求的状态

2026-10-12，用户进一步要求删除除B2外的CoreMark文件。
整批删除旧备份、ZIP、审计和历史资料被自动审批拒绝，要求对恢复/追溯资料单独明确确认。
已按较安全范围删除554个可重建的非B2镜像、编译产物、编译库文件及B1/LTO构建脚本。
历史日志、JSON、ZIP、备份、reclone和审计资料暂保留；不能声称已完成全部删除。
rebuildable_cleanup_plan.json记录已删除的文件和保护哈希；non_b2_cleanup_plan.json是原更大范围清单，
再次操作前必须核对当前文件存在情况，并取得对这些历史资料的明确确认。
B2四组镜像、活动DAT、共享官方源码、CPU RTL和ISA用例哈希核对不变。

2026-10-12，用户授权重新生成B2并删除其他未采用DAT。

## 完成内容

- GCC15.2.0、rv32im_zba_zicsr、O3、无LTO，重新编译四组：上板performance_long/validation（4000、83333333Hz）及sim_performance/sim_validation（10、100MHz）。
- 四组编译/链接退出码0，没有warning/error诊断；官方六个核心文件规范化哈希通过，ELF/HEX匹配。
- 每组代码21836B，DAT深度8192/32768，无BOM纯LF；哈希与对应新manifest一致。
- 根目录两份活动DAT成对切为B2 performance_long，选择脚本默认也改为该包。
- B2生成脚本默认四组，不再默认生成可能不足10秒的2200次版；仍可显式指定旧performance预设，但当前该DAT已删除。
- ROM生成内容已由用户更新为B2，本次解码8192字核对完全匹配。
- RAM原生成内容仍为B4，本次通过PDS随附的原始createCasParam.tcl/createInitFile.tcl更新为B2，32768字解码核对完全匹配。
- RAM包装.v中的初始化路径同步B2；端口、结构、器件、时钟和其他参数未改变。两个.idf本来已为B2。
- 没有修改CPU RTL、官方CoreMark或约束，没有运行动态仿真、完整PDS实现、位流生成或下载。

## IP 生成方法

IP Compiler GUI程序不接受`-batch`，尝试未完成生成，因此没有把它记录为成功的完整IP重生成。
实际使用Python的Tcl解释器调用PDS安装目录原始初始化生成脚本，UI参数来自当前.idf，
布尔值按GUI接口转换为0/1，保留CAS_MODE_SEL=AUTO等原配置。
先用B4输入生成并核对所有旧RAM常量一致，再用B2输入生成并解码所有32768字一致，最后同步初始化文件和包装路径。
该方式只更新初始化数据，不修改IP结构；过程与生成器SHA256见ram_regeneration.json。
原IP生成文件完整备份在ip_generated_before.zip，源码检查见refresh_ram_init.py。

## DAT 清理范围

删除50个普通DAT文件：B1/B3/B4、旧A1官方包、重复fresh/reclone导出和旧选择备份、
B2旧2200次版、B4解码审计DAT。旧CoreMark ZIP中的40个DAT条目也已移除，其余成员保留。
删除前逐个解析绝对路径确认在仓库内，核对SHA256与清理计划一致；没有递归删除目录。
ISA测试、板级demo、源代码、ELF/HEX、历史日志和参数记录保留。
旧包manifest中的DAT哈希作为历史证据保留，但增加dat_distribution_status标明DAT已删除。
旧IP审计的JSON及生成参数源码快照仍保留，其原B4解码DAT已删除。

当前普通CoreMark DAT共10份：四组B2各2份，加根目录活动2份。
新完整ZIP为../coremark_b2_2026-10-12.zip，包含四组共8份DAT。

## 记录

- build_all.log：本次四组编译/导出日志。
- fpga/pds/...：重建前B2 manifest、汇总及采用配置快照，保留旧板测证据。
- rtl_inputs_before.json：CPU RTL/宏在整个任务前后的哈希基线。
- cleanup_plan.json：50个删除文件及40个ZIP删除条目的原路径、哈希和范围。
- archive_cleanup.json：旧ZIP修改前后哈希。
- summary.json：四组镜像与当前IP初始化一致性结果。
- prepare_cleanup.py、clean_archives.py、finalize.py：本次清理与核对记录脚本。

下一步：从Compile重新执行PDS完整流程、生成新位流后下载。
旧位流并未因DAT/IP初始化更新而自动变化；新RTL+B2的性能/验证结果需用户上板提供。
