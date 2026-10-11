// =====================================================================
//  irom_bram —— PDS "DRM Based ROM" IP 的行为级仿真模型(仅仿真用)
//  接口与 student_top 中例化的 irom_bram 一致: clk / rst / addr(13位字地址) / rd_data(32位)
//  同步读(latency-1,地址寄存),匹配真实 ROM(无输出寄存器)。
//  尺寸: 8192 字 = 32KB  (原 4096 字 = 16KB; 为装下 CoreMark 的 5344 条指令扩容)
// =====================================================================
module irom_bram #(
    parameter HEX = "sim/irom.hex"     // 由 COE/*.coe 转出的 hex
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [12:0] addr,
    output reg  [31:0] rd_data
);
  localparam WORDS = 8192;             // 32KB = 8192 字
  reg [31:0] rom [0:WORDS-1];
  integer k;
  reg [1023:0] irom_file;
  initial begin
    for (k = 0; k < WORDS; k = k + 1) rom[k] = 32'h00000013; // 默认 NOP
    // +irom=<path> 可覆盖默认镜像(仿真用,方便跑不同程序)
    if (!$value$plusargs("irom=%s", irom_file)) irom_file = HEX;
    $readmemh(irom_file, rom);
    rd_data = 32'h00000013;
  end
  always @(posedge clk) begin
    if (rst) rd_data <= 32'h00000013;
    else     rd_data <= rom[addr];
  end
endmodule
