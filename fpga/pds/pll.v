// #############################################################################
// ⚠️ 本文件已作废（2026-10-03），不要加进 PDS 工程，留在这里只为说明历史方案。
//
// 它原本是"把 PDS 的 PLL IP 包装成 Vivado 端口名"的包装层，面向的是**早期设想**：
// 板上 200 MHz 差分时钟 + GTP_INBUFDS + IP 实例名 pll_ip。
//
// 现在工程的实际做法（见 fpga/pds/README.md 第 9 节）：
//   * 板上时钟是 **50 MHz 单端**（管脚 P20），不用差分缓冲；
//   * PLL 直接用 IP 向导生成，实例名就叫 **pll**、文件在 ipcore/pll/pll.v，
//     rtl/perip/top.sv 直接例化它，中间不需要任何包装层；
//   * 器件已从 Logos/PGL50H 换成 **Logos2/PG2L50H**，PLL 是
//     ipm2l_pll_wrapper_v1_1（内部原语 u_gpll）：
//         CLKIN = 50.0 MHz, IDIV = 1, FDIV = 15  ->  VCO = 750 MHz
//         ODIV0 = 15, DUTY0 = 15  ->  clkout0 = 50.000 MHz（UART / twin_controller）
//         ODIV1 =  9, DUTY1 =  9  ->  clkout1 = 83.333 MHz（CPU）
//   * ⚠️ 端口名差异：Logos 版锁定输出叫 **pll_lock**，Logos2 版叫 **lock**，
//     换 IP 时 top.sv 的例化必须跟着改（否则报端口不存在）。
//
// 需要看真正的 PLL 定义请直接看：ipcore/pll/pll.v（PDS 工程目录内）
// #############################################################################
