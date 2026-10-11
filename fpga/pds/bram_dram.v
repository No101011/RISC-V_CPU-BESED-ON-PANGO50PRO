// #############################################################################
// ⚠️ 不要把这个文件加进 PDS 工程！
//    工程里已经生成了同名模块 ipcore/bram_dram/bram_dram.v（端口 wr_*/rd_*），
//    rtl/perip/dram_driver.sv 已按那套端口改好。本文件模块名同为 bram_dram，
//    一起加入会报模块重复定义。仅在走"包装层方案"时才用。
// #############################################################################
//=============================================================================
// bram_dram.v  —— PDS（紫光同创）版 DRAM 包装
//
// 作用：把 PDS 生成的 "DRM Based Simple Dual Port RAM" IP 包装成与 Vivado
//       Block Memory Generator（Simple Dual Port RAM）完全同名的端口，
//       这样 rtl/perip/dram_driver.sv 一行都不用改。
//
// 对应 Vivado 侧配置（bram_dram）：
//   Memory Type      : Simple Dual Port RAM
//   Port A Width/Depth: 32 / 65536   (16 位地址)
//   Port B Width/Depth: 32 / 65536
//   Write Enable     : Byte Write Enable, Byte Size = 8  -> wea[3:0]
//   Port A/B Enable  : Use ENA / ENB Pin
//   无输出寄存器（读延迟 1 拍）
//
// PDS 侧需要先在 IP 向导里生成名为 bram_dram_ip 的 IP（配置见 README.md），
// 并且必须勾上：
//   [x] Write/Read Port Use Same Data Width
//   [x] Enable Byte Write           Byte Size = 8   Byte Numbers = 4
//   [x] Enable rd_clk_en Signal     （用来接 Vivado 的 enb）
//   [ ] Enable Output Register      （千万别勾，勾了读延迟变 2 拍）
//   [ ] Enable rd_oce Signal
//   Write/Read Address Width = 16,  Data Width = 32
//=============================================================================
`timescale 1ns / 1ps

module bram_dram (
    input  wire        clka   ,   // 写时钟
    input  wire        ena    ,   // Vivado 端口 A 使能（原设计恒 1）
    input  wire [3:0]  wea    ,   // 字节写使能
    input  wire [15:0] addra  ,   // 写地址
    input  wire [31:0] dina   ,   // 写数据
    input  wire        clkb   ,   // 读时钟
    input  wire        enb    ,   // Vivado 端口 B 使能（原设计恒 1）
    input  wire [15:0] addrb  ,   // 读地址
    output wire [31:0] doutb      // 读数据（延迟 1 拍）
);

    // PDS 的伪双口 RAM：wr_en=1 才写，wr_byte_en 决定写哪几个字节；
    //                  读口每个 rd_clk 上升沿按 rd_addr 取值，延迟 1 拍。
    bram_dram_ip U_bram_dram_ip (
        .wr_clk      (clka            ),   // input
        .wr_rst      (1'b0            ),   // input  不复位，等价 Vivado 无 rst
        .wr_en       (ena & (|wea)    ),   // input  有字节使能才写
        .wr_addr     (addra           ),   // input  [15:0]
        .wr_data     (dina            ),   // input  [31:0]
        .wr_byte_en  (wea             ),   // input  [3:0]
        .rd_clk      (clkb            ),   // input
        .rd_rst      (1'b0            ),   // input
        .rd_clk_en   (enb             ),   // input  需勾 "Enable rd_clk_en Signal"
        .rd_addr     (addrb           ),   // input  [15:0]
        .rd_data     (doutb           )    // output [31:0]
    );

endmodule
