// =====================================================================
//  bram_dram —— PDS "DRM Based Simple Dual Port RAM" IP 的行为级仿真模型（仅仿真用）
//  接口与 dram_driver.sv 中例化的 bram_dram 一致: wr_* 写口 / rd_* 读口, latency-1。
//  尺寸: 32768 字 x 32bit = 128KB   (原 65536 字 = 256KB; PGL50H 的 DRM 放不下)
//  读口无字节写回 mux → 真实 IP 读路径更短(EX1→w_mem_rdata 是 Fmax 最差路径)。
//  读写同址同拍=READ_FIRST(读旧值)，CPU 侧 st_conflict 护栏保证该情形不发生提前读。
// =====================================================================
module bram_dram #(
    parameter HEX = "sim/dram.hex"
) (
    input  wire        wr_clk,
    input  wire        wr_rst,
    input  wire        wr_en,
    input  wire [14:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [ 3:0] wr_byte_en,
    input  wire        rd_clk,
    input  wire        rd_rst,
    input  wire        rd_clk_en,
    input  wire [14:0] rd_addr,
    output reg  [31:0] rd_data
);
  localparam WORDS = 32768;            // 128KB = 32768 字
  reg [31:0] mem [0:WORDS-1];
  integer k;
  reg [1023:0] dram_file;
  initial begin
    for (k = 0; k < WORDS; k = k + 1) mem[k] = 32'h0;
    if (!$value$plusargs("dram=%s", dram_file)) dram_file = HEX;
    $readmemh(dram_file, mem);
    rd_data = 32'h0;
  end

  // 写口：字节使能
  always @(posedge wr_clk) begin
    if (wr_en) begin
      if (wr_byte_en[0]) mem[wr_addr][ 7: 0] <= wr_data[ 7: 0];
      if (wr_byte_en[1]) mem[wr_addr][15: 8] <= wr_data[15: 8];
      if (wr_byte_en[2]) mem[wr_addr][23:16] <= wr_data[23:16];
      if (wr_byte_en[3]) mem[wr_addr][31:24] <= wr_data[31:24];
    end
  end

  // 读口：latency-1，READ_FIRST（NBA 读到本拍写之前的旧值）
  always @(posedge rd_clk) begin
    if (rd_rst)        rd_data <= 32'h0;
    else if (rd_clk_en) rd_data <= mem[rd_addr];
  end
endmodule
