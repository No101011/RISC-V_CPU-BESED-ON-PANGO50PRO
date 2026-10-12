# 用户修改的 EX2 L0 查询：代码检查

2026-10-12。范围：只检查用户手动加入的仅LW EX2 L0查询，没有修改CPU RTL。

## 结果

静态检查没有发现本次改动中的功能接线问题，五处修改与提供的示例一致：

- L0第二读口使用EX2实际字地址，与原读口共用当前数据、标签、有效位。
- 命中限制有效LW、自然对齐、DRAM范围、复位及后端停顿；MEM1/WB同字store均阻止命中。
- 命中判断没有使用总stall，不引入由load依赖停顿反馈到自身ready的组合环。
- mem1_fwd_pre接入新数据，优先级低于原D1、SB、store直传和提前读取路径。
- e2_ld_ready在两种宏分支都接入新命中，现有hazard和预选forward使用该信号。
- 原ex2_rd_issue、读地址选择、m1_ex2_rd和WB写回路径保留，没有取消普通BRAM读取。
- 当前SUBWORD_FAST开启、SUBWORD_SPEC关闭，新增LW整字转发不经过子字格式化。

ModelSim SE-64 2020.4：vlog编译和vopt展开均0 Errors / 0 Warnings，退出码0。
在sim/programs目录运行compile.do；仅编译/展开，没有执行run命令。
所有输入SHA256在编译前后相同。日志和脚本见compile.log、compile.do，输入快照及哈希随报告保存。

git diff --check仅发现两处行尾空格：l0_cache.v:33、myCPU.sv:50，不影响功能。

## 验证范围

本次没有运行CoreMark动态仿真、同址store定向用例、ISA回归或PDS实现。
因此不代表CRC、实际性能或新RTL的时序已经通过。
原先CPU WNS=+0.935ns属于改动前实现；新增读口可能改变分布式RAM映射与就绪路径。
前次仅LW影子机会57343周期、静态估计约1.66%提升仍只是实现前估算。
