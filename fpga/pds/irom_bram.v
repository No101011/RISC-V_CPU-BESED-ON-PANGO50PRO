// #############################################################################
// ⚠️ 不要把这个文件加进 PDS 工程！
//    工程里已经生成了同名模块 ipcore/irom_bram/irom_bram.v（端口 clk/rst/addr/rd_data），
//    rtl/perip/student_top.sv 已按那套端口改好。本文件模块名同为 irom_bram，
//    一起加入会报模块重复定义。仅在走"包装层方案"时才用。
// #############################################################################
//=============================================================================
// irom_bram.v  —— PDS（紫光同创）版 IROM 包装
//
// 作用：把 PDS 生成的 "DRM Based ROM" IP 包装成与 Vivado 侧 irom_bram
//       完全同名的端口（clka/addra/douta），student_top.sv 无需改动。
//
// 对应 Vivado 侧配置：
//   单口 ROM，Width 32 / Depth 4096（12 位地址），由 .coe 初始化，无输出寄存器。
//
// PDS 侧需要先生成名为 irom_bram_ip 的 IP（配置见 README.md），必须：
//   Address Width = 12      Data Width = 32
//   [x] Init Enable         Init File = irom.dat（用 coe2dat.py 转换）
//   Initial Data Format Type = HEX
//   [ ] Enable Output Register   （别勾，勾了读延迟变 2 拍）
//   Reset Type = ASYNC
//=============================================================================
`timescale 1ns / 1ps

module irom_bram (
    input  wire        clka ,   // 读时钟
    input  wire [11:0] addra,   // 读地址（字地址，pc[13:2]）
    output wire [31:0] douta    // 读数据（延迟 1 拍）
);

    // PDS 的 DRM Based ROM：每个 clk 上升沿按 addr 取值，延迟 1 拍。
    irom_bram_ip U_irom_bram_ip (
        .clk      (clka ),   // input
        .rst      (1'b0 ),   // input  不复位（ROM 内容由 .dat 配置进去）
        .addr     (addra),   // input  [11:0]
        .rd_data  (douta)    // output [31:0]
    );

endmodule
