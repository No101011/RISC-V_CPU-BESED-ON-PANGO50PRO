`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:13 PM
// Design Name: 
// Module Name: student_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module student_top#(
    parameter                           P_SW_CNT            = 64,
    parameter                           P_LED_CNT           = 32,
    parameter                           P_SEG_CNT           = 40,
    parameter                           P_KEY_CNT           = 8
) (
    input                                       w_cpu_clk     ,
    input                                       w_clk_50Mhz   ,
    input                                       w_clk_rst     ,
    input  [P_KEY_CNT - 1:0]                    virtual_key   ,
    input  [P_SW_CNT  - 1:0]                    virtual_sw    ,

    output [P_LED_CNT - 1:0]                    virtual_led   ,
    output [P_SEG_CNT - 1:0]                    virtual_seg   ,

    // CoreMark 魔法 UART 桥（见 perip_bridge.sv / top.sv）
    output                                      cm_req_tog    ,
    output [7:0]                                cm_tx_byte    ,
    output                                      cm_done       ,
    input                                       cm_ack_tog
);

    // IROM双发取指:A 口=pc,B 口=pc+4
    // irom_bram IP,例化了两份
    logic [31:0] pc, pc2;
    // 32KB IROM 即  2^13 * 32bit，15位 地址空间，按 4byte 对齐
    //   （原 16KB/12位；为装下 CoreMark 的 5344 条指令扩到 8192 字 = 32KB）
    logic [12:0] inst_addr, inst_addr2;
    logic [31:0] instruction, instruction2;

    // perip
    logic [31:0] perip_addr, perip_raddr, perip_wdata, perip_rdata, perip_rdram;
    logic perip_wen;
    logic [1:0] perip_mask;

    assign inst_addr  = pc[14:2];
    assign inst_addr2 = pc2[14:2];

    myCPU Core_cpu (
        .cpu_rst            (w_clk_rst),
        .cpu_clk            (w_cpu_clk),

        // Interface to IROM
        .irom_addr          (pc),               //IROM 
        .irom_data          (instruction),   
        .irom_addr2         (pc2),    
        .irom_data2         (instruction2),     //IROM B

        // Interface to DRAM & periphera
        .perip_addr         (perip_addr),
        .perip_raddr        (perip_raddr),
        .perip_wen          (perip_wen),
        .perip_mask         (perip_mask),   
        .perip_wdata        (perip_wdata),
        .perip_rdata        (perip_rdata),
        .perip_rdram        (perip_rdram)
    );

    // 注意指令存储器更换为BRAM，为同步读需等一拍
    // PDS 版 DRM Based ROM 的端口是 clk / rst / addr / rd_data（不是 Vivado 的 clka/addra/douta）
    irom_bram Mem_IROM (
        .clk        (w_cpu_clk),
        .rst        (1'b0),
        .addr       (inst_addr),
        .rd_data    (instruction)
    );

    irom_bram Mem_IROM_B (
        .clk        (w_cpu_clk),
        .rst        (1'b0),
        .addr       (inst_addr2),
        .rd_data    (instruction2)
    );
    
    //数据存储器更改为简单双口，vivado里面Simple Dual Port A口只写，B口只读
    perip_bridge bridge_inst (
        .clk				(w_cpu_clk),
        .cnt_clk            (w_clk_50Mhz),
        .rst                (w_clk_rst),
        .perip_addr			(perip_addr),   //B口只读，读地址
        .perip_raddr		(perip_raddr),  //A口只写，写地址
        .perip_wdata		(perip_wdata),  //A口写数据
        .perip_wen			(perip_wen),    
        .perip_mask			(perip_mask),
        .perip_rdata		(perip_rdata),  //B口只读，选路后的读数据
        .perip_rdram		(perip_rdram),  //B口只读，原始数据数据
        .virtual_sw_input	(virtual_sw),
        .virtual_key_input	(virtual_key),	
        .virtual_seg_output	(virtual_seg),
        .virtual_led_output (virtual_led),
        .cm_req_tog         (cm_req_tog),
        .cm_tx_byte         (cm_tx_byte),
        .cm_done            (cm_done),
        .cm_ack_tog         (cm_ack_tog)
    );

endmodule
