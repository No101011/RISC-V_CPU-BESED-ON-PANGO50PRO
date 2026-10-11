`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: top —— 盘古50Pro / MES2L50HP（PG2L50H-FBG484-6）
//
//   1) 使用核心板的 125 MHz 差分晶振：V4=P、W4=N，经 GTP_INBUFDS 输入 PLL。
//      原理图 R73 已有 100 Ohm 端接，关闭输入缓冲的内部端接。
//      CLKIN=125、IDIV=1、MDIV=1、FDIV=6 -> VCO=750 MHz，
//      ODIV0=15 -> UART 50 MHz，ODIV1=9 -> CPU 83.333 MHz。
//   2) led[0..7] 对应 LED1..8：F13 F14 E13 E14 E16 D16 F16 E17，高电平点亮。
//   3) USB-UART：TX=K19、RX=P14，9600-8-N-1。
//   4) CoreMark UART 桥保持 CPU 请求到 50 MHz 域的握手；cm_done 使 8 个 LED 全亮。
//
// 脚位依据见 fpga/pds/pins.fdc 头部注释（来源是开发板资料里厂商 demo 的 fdc）。
//////////////////////////////////////////////////////////////////////////////////


module top(
    input  wire        clk_125m_p   ,   // V4  125 MHz LVDS，BANK R5 = 1.5 V
    input  wire        clk_125m_n   ,   // W4  125 MHz LVDS，BANK R5 = 1.5 V
    input  wire        i_uart_rx    ,   // P14 板上 USB-UART -> FPGA
    output wire        o_uart_tx    ,   // K19 FPGA -> 板上 USB-UART
    output wire [7:0]  led              // LED1..8，BANK L3 = 3.3 V
);

    wire clk_125m;
    // Port I/O standard is set in pins.fdc, matching the vendor DDR3 demo.
    GTP_INBUFDS #(.TERM_DIFF("OFF")) clk_inbuf_inst (
        .I(clk_125m_p), .IB(clk_125m_n), .O(clk_125m)
    );

    wire w_clk_50Mhz;        // PLL clkout0 = 50 MHz  （UART / twin_controller）
    wire cpu_clk;            // PLL clkout1 = 83.33 MHz（CPU）
    wire w_clk_rst;          // PLL lock（Logos2 IP 叫 lock；未锁定=0）

    wire [7:0]  virtual_key;
    wire [63:0] virtual_sw;
    wire [31:0] led_bus;
    wire [39:0] seg_bus;     // 板上没有数码管，不引出（会被综合剪掉）

    wire [7:0] rx_data;
    wire rx_ready;
    wire [7:0] twin_tx_data;
    wire twin_tx_start;
    wire tx_busy;

    // ------------------------------------------------------------------
    // CoreMark 魔法 UART 桥：CPU 域请求 -> 50 MHz 域 UART 发送
    //   CPU 侧（perip_bridge）每写一个字符把 cm_req_tog 翻转一次；
    //   这里同步过来、在 UART 空闲时发一个 1 拍 tx_start，并把 cm_ack_tog 翻回去；
    //   软件发下一个字符前会轮询 0xF000_0008 的忙位，所以不会丢字符、也不需要 FIFO。
    // ------------------------------------------------------------------
    wire        cm_req_tog;
    wire [7:0]  cm_tx_byte;
    wire        cm_done;
    reg         cm_ack_tog;          // 在下面的 always 块里翻转，所以是 reg
    reg         cm_req_s1, cm_req_s2;
    reg  [7:0]  cm_byte_50;
    reg         cm_start_50;

    always @(posedge w_clk_50Mhz) begin
        if (!w_clk_rst) begin            // w_clk_rst = pll_lock，未锁定时复位
            cm_req_s1   <= 1'b0;
            cm_req_s2   <= 1'b0;
            cm_byte_50  <= 8'd0;
            cm_start_50 <= 1'b0;
            cm_ack_tog  <= 1'b0;
        end else begin
            cm_req_s1   <= cm_req_tog;
            cm_req_s2   <= cm_req_s1;
            cm_start_50 <= 1'b0;                     // 默认拉低 -> 1 拍脉冲
            if ((cm_req_s2 != cm_ack_tog) && !tx_busy) begin
                cm_byte_50  <= cm_tx_byte;           // 此刻字符已稳定（软件在等忙位）
                cm_start_50 <= 1'b1;
                cm_ack_tog  <= cm_req_s2;
            end
        end
    end

    // UART 发送复用：CoreMark 文本优先。跑 CoreMark 时别开数字孪生上位机（同一个串口）。
    wire [7:0] uart_tx_data  = cm_start_50 ? cm_byte_50 : twin_tx_data;
    wire       uart_tx_start = cm_start_50 | twin_tx_start;

    // Logos2 版 PLL IP（ipm2l_pll_wrapper_v1_1，内部原语 u_gpll）的端口：
    //   clkin1 / clkout0 / clkout1 / lock
    //   核心板 125 MHz 差分时钟先经 clk_inbuf_inst，再接 clkin1。
    //   ⚠️ Logos 版 IP 的锁定输出叫 pll_lock，Logos2 版改名叫 lock —— 换 IP 时这里要跟着改
    //   clkout0 = 50.00 MHz (CLKIN=125, IDIV=1, MDIV=1, FDIV=6 -> VCO=750 MHz, ODIV0=15)
    //   clkout1 = 83.33 MHz (ODIV1=9)
    pll pll_inst(
        .clkin1   (clk_125m    ),
        .clkout0  (w_clk_50Mhz ),
        .clkout1  (cpu_clk     ),
        .lock     (w_clk_rst   )
    );

    uart #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(9600)
    ) uart_inst(
        .clk(w_clk_50Mhz),
        .rst_n(w_clk_rst),
        .rx(i_uart_rx),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .tx(o_uart_tx),
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_busy(tx_busy)
    );

    twin_controller twin_controller_inst(
        .clk(w_clk_50Mhz),
        .rst_n(w_clk_rst),
        .rx_ready(rx_ready),
        .rx_data(rx_data),
        .tx_start(twin_tx_start),
        .tx_data(twin_tx_data),
        .tx_busy(tx_busy),
        .sw(virtual_sw),
        .key(virtual_key),
        .seg(seg_bus),
        .led(led_bus)
    );

    student_top student_top_inst(
        .w_cpu_clk(cpu_clk),
        .w_clk_50Mhz(w_clk_50Mhz),
        .w_clk_rst(~w_clk_rst),
        .virtual_key(virtual_key),
        .virtual_sw(virtual_sw),
        .virtual_led(led_bus),
        .virtual_seg(seg_bus),
        .cm_req_tog(cm_req_tog),
        .cm_tx_byte(cm_tx_byte),
        .cm_done(cm_done),
        .cm_ack_tog(cm_ack_tog)
    );

    // 8 个 LED：平时显示 LED 寄存器（0x8020_0040）；CoreMark 跑完（cm_done）全亮
    assign led = led_bus[7:0] | {8{cm_done}};

endmodule
