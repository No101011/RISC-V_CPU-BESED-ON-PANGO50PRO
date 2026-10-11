`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/04/22 10:25:24
// Design Name: 
// Module Name: perip_bridge
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

module perip_bridge(
    input  logic         clk				,
    input  logic         cnt_clk			,
    input  logic         rst                ,

    input  logic [31:0]  perip_addr			,
    input  logic [31:0]  perip_raddr		,   // DRAM 读口独立地址,仅透传给 dram_driver
    input  logic [31:0]  perip_wdata		,
    input  logic         perip_wen			,
	input  logic [1:0]	 perip_mask			,
    output logic [31:0]  perip_rdata		,
    output logic [31:0]  perip_rdram		,   // DRAM 读口原始数据透传

    input  logic [63:0]  virtual_sw_input	,
    input  logic [7:0]   virtual_key_input	,	

	output logic [39:0]  virtual_seg_output	,
    output logic [31:0]  virtual_led_output ,

    // ---- CoreMark 魔法 UART 桥（0xF000_0000 写字符 / 0xF000_0004 结束 / 0xF000_0008 读忙）----
    //   cm_req_tog ：CPU 域，每写一个字符翻转一次（跨时钟握手的请求）
    //   cm_tx_byte ：CPU 域，要发的字符（软件会等到不忙才写下一个，所以电平稳定）
    //   cm_done    ：CPU 域，CoreMark 跑完的标志
    //   cm_ack_tog ：50MHz 域回送的应答（在 top.sv 的 UART 侧翻转）
    // 板上没接魔法 UART 时这几个信号悬空即可，不影响其它功能。
    output logic         cm_req_tog			,
    output logic [7:0]   cm_tx_byte			,
    output logic         cm_done			,
    input  logic         cm_ack_tog
);
    localparam DRAM_ADDR_START = 32'h8010_0000;
    localparam DRAM_ADDR_END   = 32'h8012_0000;  // 128KB（原 256KB：PGL50H 的 DRM 放不下，见 README）
                                                 // 判据用 "< END"，所以 END 取开区间上界
    localparam SW0_ADDR  = 32'h8020_0000;  // sw[31:0]
    localparam SW1_ADDR  = 32'h8020_0004;  // sw[63:32]
    localparam KEY_ADDR  = 32'h8020_0010;  // key[7:0]
    localparam SEG_ADDR  = 32'h8020_0020;  // seg
    localparam LED_ADDR  = 32'h8020_0040;  // led[31:0]
    localparam CNT_ADDR  = 32'h8020_0050;  // counter
    localparam CNT_START_CMD = 32'h8000_0000;
    localparam CNT_STOP_CMD  = 32'hFFFF_FFFF;
    // CoreMark 的 printf 走这三个地址（仿真台 tb_myCPU 里是 $write，板上就是这条通路）
    localparam MAGIC_UART = 32'hF000_0000;  // 写：输出一个字符
    localparam MAGIC_EXIT = 32'hF000_0004;  // 写：跑完了
    localparam MAGIC_STAT = 32'hF000_0008;  // 读：bit0 = 发送忙

    logic [31:0] LED;
    logic [31:0] seg_wdata, cnt_rdata, mmio_rdata, dram_rdata;
    logic [39:0] seg_output;
    logic cnt_enable_cfg;

    // ---- 魔法 UART：CPU 域一边 ----
    logic cm_ack_s1, cm_ack_s2;              // 50MHz 域的 ack 同步回 CPU 域（2 级）
    wire  cm_busy = (cm_ack_s2 != cm_req_tog);   // 还有字符在途 -> MAGIC_STAT 读出来是 1
    always_ff @(posedge clk) begin
        if (rst) begin
            cm_req_tog  <= 1'b0;
            cm_tx_byte  <= 8'd0;
            cm_done     <= 1'b0;
            cm_ack_s1   <= 1'b0;
            cm_ack_s2   <= 1'b0;
        end else begin
            cm_ack_s1 <= cm_ack_tog;
            cm_ack_s2 <= cm_ack_s1;
            if (perip_wen) begin
                if (perip_addr == MAGIC_UART) begin
                    cm_tx_byte <= perip_wdata[7:0];
                    cm_req_tog <= ~cm_req_tog;
                end else if (perip_addr == MAGIC_EXIT && perip_wdata != 32'h0) begin
                    cm_done    <= 1'b1;
                end
            end
        end
    end

    // we don't care perip_mask in LED, SEG, SW & KEY, only care in DRAM
    // write process
    always_ff @(posedge clk) begin
        if (rst) begin
            LED            <= 32'd0;
            seg_wdata      <= 32'd0;
            cnt_enable_cfg <= 1'b0;
        end else if (perip_wen) begin
            case (perip_addr)
                LED_ADDR:   LED <= perip_wdata;
                SEG_ADDR:   seg_wdata <= perip_wdata;
                CNT_ADDR: begin
                    if (perip_wdata == CNT_START_CMD) begin
                        cnt_enable_cfg <= 1'b1;
                    end else if (perip_wdata == CNT_STOP_CMD) begin
                        cnt_enable_cfg <= 1'b0;
                    end
                end
            endcase
        end
    end

    // read process: in one cycle
    always_comb begin
        if (~perip_wen) begin
            case (perip_addr)
                SW0_ADDR:  mmio_rdata = virtual_sw_input[31:0];
                SW1_ADDR:  mmio_rdata = virtual_sw_input[63:32];
                KEY_ADDR:  mmio_rdata = {24'd0, virtual_key_input};
                SEG_ADDR:  mmio_rdata = seg_wdata;
                default:   mmio_rdata = 32'hDEAD_BEEF;
            endcase
        end else begin
            mmio_rdata = 32'h0;
        end
    end

    // seg driver
    display_seg seg_driver (
        .clk    (clk),
        .rst    (rst),
        .s      (seg_wdata),
        .seg1   (seg_output[6:0]),
        .seg2   (seg_output[16:10]),
        .seg3   (seg_output[26:20]),
        .seg4   (seg_output[36:30]),
        .ans    ({seg_output[39:38], seg_output[29:28], seg_output[19:18], seg_output[9:8]})
    ); 
   
    assign seg_output[7]  = 0;
    assign seg_output[17] = 0;
    assign seg_output[27] = 0;
    assign seg_output[37] = 0;
    

    // dram rw
    dram_driver dram_driver_inst (
        .clk				(clk),
        .perip_addr			(perip_addr[17:0]),
        .perip_raddr		(perip_raddr[17:0]),
        .perip_rdram		(perip_rdram),
        .perip_wdata		(perip_wdata),
        .perip_mask			(perip_mask),
        .dram_wen 			(perip_wen & (perip_addr >= DRAM_ADDR_START && perip_addr < DRAM_ADDR_END)),
        .perip_rdata		(dram_rdata)
    );

    // counter rw
    counter counter_inst (
        .cpu_clk            (clk),
        .cnt_clk            (cnt_clk),
        .rst                (rst),
        .cnt_enable_cpu     (cnt_enable_cfg),
        .perip_rdata		(cnt_rdata)
    );

    // DRAM 读数据是最迟到达的慢信号,让它只过一个 2:1 选择器直达输出;
    //   MMIO(SW/KEY/SEG/CNT)都是寄存器源、提前就绪,先用与-或树并成一路,
    //   再与 DRAM 数据二选一。选择信号来自已寄存的地址,同样提前就绪。
    //   地址映射:DRAM 区→dram_rdata;各外设→对应寄存器;未命中地址→0。
    wire        is_dram_rd   = (perip_addr >= DRAM_ADDR_START && perip_addr < DRAM_ADDR_END);
    wire [31:0] cm_stat       = {31'd0, cm_busy};     // MAGIC_STAT：bit0 = 发送忙
    wire [31:0] mmio_combined = {32{perip_addr == SW0_ADDR}} & mmio_rdata |
                               {32{perip_addr == SW1_ADDR}} & mmio_rdata |
                               {32{perip_addr == KEY_ADDR}} & mmio_rdata |
                               {32{perip_addr == SEG_ADDR}} & mmio_rdata |
                               {32{perip_addr == CNT_ADDR}} & cnt_rdata |
                               {32{perip_addr == MAGIC_STAT}} & cm_stat;
    assign perip_rdata = is_dram_rd ? dram_rdata : mmio_combined;
    
    assign virtual_led_output = LED;
    assign virtual_seg_output = seg_output;

endmodule
