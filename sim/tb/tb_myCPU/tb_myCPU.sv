// ============================================================================
// tb_myCPU.sv —— 简化版仿真平台
//   1. IROM 读 imem.hex，给 CPU 取指（两个读口：A=pc、B=pc|4，与 FPGA 上两份 irom_bram 一致）。
//   2. DRAM 读 dmem.hex，给 CoreMark 等程序使用；读写分口，读口地址走 perip_raddr。
//   3. TEST_MODE=1 时，额外打开低地址内存，适配 riscv-tests。
//   4. 0xF000_0000/0xF000_0004 分别作为 magic UART / EXIT。
//
// 重要：存储器和 FPGA 上的 IP 必须同拍数。
//   irom_bram / bram_dram 都是同步读（地址打一拍才出数），所以这里必须用
//   always @(posedge clk) 寄存输出，不能写成 assign rom[addr] 的组合读 ——
//   组合读会让取指队列在"发地址那一拍"就收到数，整条流水拿到的都是错拍的指令。
// ============================================================================
`timescale 1ns / 1ps

module tb_myCPU #(
    parameter IROM_HEX   = "imem.hex",
    parameter DRAM_HEX   = "dmem.hex",
    parameter MAX_CYCLES = 64'd200_000_000,
    parameter TEST_MODE  = 0
) ();

  // 时钟复位：100MHz，复位 100ns 后释放
  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  initial begin
    #100 rst = 1'b0;
  end

  // DUT 接口（13 个端口全部接上，缺一个输入就是 X，整条流水会跟着变 X）
  wire [31:0] irom_addr, irom_data;
  wire [31:0] irom_addr2, irom_data2;
  wire [31:0] perip_addr, perip_wdata, perip_rdata;
  wire [31:0] perip_raddr, perip_rdram;
  wire        perip_wen;
  wire [ 1:0] perip_mask;

  myCPU u_cpu (
      .cpu_rst    (rst),
      .cpu_clk    (clk),
      .irom_addr  (irom_addr),
      .irom_data  (irom_data),
      .irom_addr2 (irom_addr2),
      .irom_data2 (irom_data2),
      .perip_addr (perip_addr),
      .perip_raddr(perip_raddr),
      .perip_wen  (perip_wen),
      .perip_mask (perip_mask),
      .perip_wdata(perip_wdata),
      .perip_rdata(perip_rdata),
      .perip_rdram(perip_rdram)
  );

  // --------------------------------------------------------------------------
  // 内存模型
  // --------------------------------------------------------------------------
  localparam IROM_WORDS = 8192;               // 32KB，与 FPGA 上 irom_bram 同尺寸
  localparam LOW_WORDS  = 16384;              // riscv-tests 低地址数据区（保持 64KB）
  localparam DRAM_WORDS = 32768;              // 128KB（原 256KB，PGL50H DRM 放不下）
  localparam DRAM_BASE  = 32'h8010_0000;

  reg [31:0] irom_mem [0:IROM_WORDS-1];       // 取指 ROM（同步读）
  reg [31:0] low_mem  [0:LOW_WORDS-1];        // riscv-tests 低地址数据区
  reg [31:0] dram_mem [0:DRAM_WORDS-1];       // CoreMark 数据区
  reg [31:0] irom_rdata_q, irom_rdata2_q;
  reg [31:0] dram_rdata_q;

  initial begin : init_mem
    integer i;
    for (i = 0; i < IROM_WORDS; i = i + 1)
      irom_mem[i] = 32'h0000_0013;            // NOP
    for (i = 0; i < LOW_WORDS; i = i + 1)
      low_mem[i] = 32'h0000_0013;
    for (i = 0; i < DRAM_WORDS; i = i + 1)
      dram_mem[i] = 32'h0;

    $readmemh(IROM_HEX, irom_mem);
    $readmemh(IROM_HEX, low_mem);
    $readmemh(DRAM_HEX, dram_mem);
    $display("[TB] IROM = %s", IROM_HEX);
    $display("[TB] DRAM = %s", DRAM_HEX);
  end

  // 取指 ROM：A 口给 pc、B 口给 pc|4，两份内容相同的 ROM（对应 FPGA 上的两份 irom_bram）
  // 同步读 latency-1：本拍给地址、下拍出数据
  always @(posedge clk) begin
    if (rst) begin
      irom_rdata_q  <= 32'h0000_0013;
      irom_rdata2_q <= 32'h0000_0013;
    end else begin
      irom_rdata_q  <= irom_mem[irom_addr [14:2]];   // 13 位字地址 → 32KB
      irom_rdata2_q <= irom_mem[irom_addr2[14:2]];
    end
  end
  assign irom_data  = irom_rdata_q;
  assign irom_data2 = irom_rdata2_q;

  wire in_low_mem = (TEST_MODE == 1) &&
                    ((perip_addr < 32'h0001_0000) ||
                     (perip_addr >= 32'h8000_0000 &&
                      perip_addr <  32'h8001_0000));
  wire in_dram    = (perip_addr >= DRAM_BASE) &&
                    (perip_addr <  DRAM_BASE + 32'h0002_0000);

  wire [13:0] low_idx   = perip_addr [15:2];
  wire [14:0] dram_widx = perip_addr [16:2];   // 写口：恒为 MEM1 地址
  wire [14:0] dram_ridx = perip_raddr[16:2];   // 读口：独立地址（投机读/提前读），不是 perip_addr
  wire [ 1:0] byte_off  = perip_addr [ 1:0];

  // 根据访存宽度和地址低两位生成字节写使能
  function automatic [3:0] byte_enable;
    input [1:0] width;
    input [1:0] off;
    begin
      case (width)
        2'b00:   byte_enable = 4'b0001 << off;                 // byte
        2'b01:   byte_enable = 4'b0011 << {off[1], 1'b0};      // half
        default: byte_enable = 4'b1111;                        // word
      endcase
    end
  endfunction

  // store byte/half 时，把低位数据扩展到每个可能写入的字节 lane
  function automatic [31:0] expand_wdata;
    input [31:0] data;
    input [1:0]  width;
    begin
      case (width)
        2'b00:   expand_wdata = {4{data[7:0]}};
        2'b01:   expand_wdata = {2{data[15:0]}};
        default: expand_wdata = data;
      endcase
    end
  endfunction

  // 按字节写使能合并新旧 word
  function automatic [31:0] write_merge;
    input [31:0] old_word;
    input [31:0] new_word;
    input [3:0]  be;
    begin
      write_merge = old_word;
      if (be[0]) write_merge[ 7: 0] = new_word[ 7: 0];
      if (be[1]) write_merge[15: 8] = new_word[15: 8];
      if (be[2]) write_merge[23:16] = new_word[23:16];
      if (be[3]) write_merge[31:24] = new_word[31:24];
    end
  endfunction

  // load byte/half/word 时，把目标字节/半字取到低位；符号扩展由 CPU 内部完成
  function automatic [31:0] read_align;
    input [31:0] word;
    input [1:0]  width;
    input [1:0]  off;
    begin
      case (width)
        2'b00: begin
          case (off)
            2'b00:   read_align = {24'h0, word[ 7: 0]};
            2'b01:   read_align = {24'h0, word[15: 8]};
            2'b10:   read_align = {24'h0, word[23:16]};
            default: read_align = {24'h0, word[31:24]};
          endcase
        end
        2'b01:   read_align = off[1] ? {16'h0, word[31:16]} :
                                         {16'h0, word[15: 0]};
        default: read_align = word;
      endcase
    end
  endfunction

  wire [3:0]  mem_be    = byte_enable(perip_mask, byte_off);
  wire [31:0] mem_wdata = expand_wdata(perip_wdata, perip_mask);

  // 写内存（写口用 MEM1 地址）；DRAM 读数据打一拍，与 bram_dram 的 latency-1 读口一致
  always @(posedge clk) begin
    if (perip_wen && in_low_mem)
      low_mem[low_idx] <= write_merge(low_mem[low_idx], mem_wdata, mem_be);

    if (perip_wen && in_dram)
      dram_mem[dram_widx] <= write_merge(dram_mem[dram_widx], mem_wdata, mem_be);

    dram_rdata_q <= dram_mem[dram_ridx];
  end

  // 读口原始数据导出：核内投机读（提前读）直接捕获这一路，不再经字节提取/桥选择
  assign perip_rdram = dram_rdata_q;

  assign perip_rdata = in_low_mem ? read_align(low_mem[low_idx], perip_mask, byte_off) :
                        in_dram    ? read_align(dram_rdata_q,   perip_mask, byte_off) :
                                     32'h0;

  // --------------------------------------------------------------------------
  // magic IO：CoreMark 用 UART 打印，用 EXIT 结束仿真
  // --------------------------------------------------------------------------
  localparam MAGIC_UART = 32'hF000_0000;
  localparam MAGIC_EXIT = 32'hF000_0004;

  always @(posedge clk) begin
    if (!rst && perip_wen) begin
      if (perip_addr == MAGIC_UART) begin
        $write("%c", perip_wdata[7:0]);
        $fflush;
        perf_uart_character(perip_wdata[7:0]);
      end
      if (perip_addr == MAGIC_EXIT && perip_wdata != 32'h0) begin
        #1; // Let the observer and DUT nonblocking assignments finish this edge.
        dump_perf("EXIT");
        $finish;
      end
    end
  end

  // 防止程序跑飞后仿真无限等待
  reg [63:0] tick = 64'd0;
  always @(posedge clk) begin
    if (rst) tick <= 64'd0;
    else begin
      tick <= tick + 64'd1;
      if (tick == MAX_CYCLES) begin
        #1;
        $display("\n[TB] TIMEOUT: MAX_CYCLES=%0d", MAX_CYCLES);
        dump_perf("TIMEOUT");
        $finish;
      end
    end
  end

  // riscv-tests 约定：x26=1 表示结束，x27=1 表示通过，x3 保存失败编号
  generate
    if (TEST_MODE == 1) begin : g_riscv_tests
      initial begin
        @(negedge rst);
        forever begin
          @(posedge clk);
          if (u_cpu.u_regfile.rf[26] === 32'h1) begin
            repeat (10) @(posedge clk);
            if (u_cpu.u_regfile.rf[27] === 32'h1)
              $display("\n[TB] PASS (cycles=%0d)", u_cpu.u_perf.perf_cycles);
            else
              $display("\n[TB] FAIL testnum=%0d (cycles=%0d)",
                       u_cpu.u_regfile.rf[3], u_cpu.u_perf.perf_cycles);
            $finish;
          end
        end
      end
    end
  endgenerate

  // Simulation-only observer. No ports, instructions, RTL control or CSR writes
  // are added to the DUT. All counters sample pre-NBA signals at the CPU edge.
  // A window includes the start CSR sample edge and excludes the stop edge;
  // its cycle count therefore equals the unsigned mcycle sample difference.
  localparam P_CYC=0, P_ARCH=1, P_UNIT=2, P_FUSED=3,
      P_BR=4, P_BRMIS=5, P_BRDIR=6, P_BRTARGET=7,
      P_JMP=8, P_JMPMIS=9, P_JMPNOT=10, P_JMPTARGET=11,
      P_SPURIOUS=12, P_REDIRECT=13, P_DRAM=14, P_DEP=15,
      P_MDU=16, P_CSR=17, P_ANY=18, P_OVERLAP=19,
      P_LD=20, P_MUL=21, P_BOTH=22, P_E1LD=23, P_E1MUL=24,
      P_E2LD=25, P_E2MUL=26, P_M1LD=27,
      P_ANY_RUN=28, P_DEP_RUN=29, P_LD_RUN=30, P_MUL_RUN=31,
      P_FEEMPTY=32, P_NORET=33, P_D1TRY=34, P_D1HIT=35,
      P_D1SB=36, P_D1L0=37, P_D1MISS=38, P_STCONFLICT=39, P_COUNT=40;
  typedef logic [P_COUNT-1:0][63:0] perf_stats_t;
  perf_stats_t perf_all = '0, perf_window = '0;
  logic [P_COUNT-1:0] perf_events;
  bit perf_enabled = 0, perf_active = 0;
  bit perf_prev_any = 0, perf_prev_dep = 0, perf_prev_ld = 0, perf_prev_mul = 0;
  bit perf_ticks_seen = 0, perf_iterations_seen = 0;
  logic [31:0] perf_start_pc = 0, perf_stop_pc = 0;
  logic [31:0] perf_start_tick = 0, perf_stop_tick = 0;
  longint unsigned perf_iterations = 0, perf_reported_ticks = 0, perf_reported_hz = 0;
  integer perf_windows = 0, perf_boundary_errors = 0, perf_csv = 0;
  integer perf_plusarg_result;
  string perf_csv_path, perf_uart_line = "", perf_run_mode = "unknown";

  // The timer's CSR value is consumed in EX1, not at function entry or WB.
  wire perf_e1_advance = u_cpu.e1_valid && !u_cpu.stall_back &&
      !u_cpu.predict_wrong && !u_cpu.trap_redirect && !u_cpu.mdu_stall;
  wire perf_timer_read = perf_e1_advance && u_cpu.e1_is_csr &&
      ((u_cpu.e1_instr & 32'hfffff07f) == 32'hb0002073);
  wire perf_start_event = perf_enabled && perf_timer_read && u_cpu.e1_pc == perf_start_pc;
  wire perf_stop_event = perf_enabled && perf_timer_read && u_cpu.e1_pc == perf_stop_pc;
  wire perf_br_event = u_cpu.e2_valid && u_cpu.e2_branch && !u_cpu.stall_back;
  wire perf_jmp_event = u_cpu.e2_valid && u_cpu.e2_jump && !u_cpu.stall_back;

  // Reuse actual dependency matches, including result readiness and source use.
  // Merely having a load/mul somewhere in the pipeline is not attribution.
  wire perf_e1ld = u_cpu.u_hazard.e1_match_any && u_cpu.u_hazard.e1_ld_only;
  wire perf_e1mul = u_cpu.u_hazard.e1_match_any && u_cpu.e1_is_mul;
  wire perf_e2ld = u_cpu.u_hazard.e2_match_any && u_cpu.e2_mem_re && !u_cpu.e2_ld_ready;
  wire perf_e2mul = u_cpu.u_hazard.e2_match_any && u_cpu.e2_is_pmul;
  wire perf_m1ld = u_cpu.u_hazard.load_use_mem1;
  wire perf_ld_dep = perf_e1ld || perf_e2ld || perf_m1ld;
  wire perf_mul_dep = perf_e1mul || perf_e2mul;
  wire perf_d1_probe = perf_e1_advance && u_cpu.e1_mem_re && u_cpu.spec_addr_valid;

  initial begin
    perf_plusarg_result = $value$plusargs("PERF_ENABLE=%d", perf_enabled);
    perf_plusarg_result = $value$plusargs("PERF_START_PC=%h", perf_start_pc);
    perf_plusarg_result = $value$plusargs("PERF_STOP_PC=%h", perf_stop_pc);
    perf_plusarg_result = $value$plusargs("PERF_ITERATIONS=%d", perf_iterations);
    if (perf_enabled && (perf_start_pc == 0 || perf_stop_pc == 0 || perf_start_pc == perf_stop_pc))
      $fatal(1, "Invalid CoreMark timer PCs");
    if ($value$plusargs("PERF_REPORT_CSV=%s", perf_csv_path)) begin
      perf_csv = $fopen(perf_csv_path, "w");
      if (!perf_csv) $display("[PERF] WARNING: cannot open CSV: %s", perf_csv_path);
      else $fdisplay(perf_csv, "scope,metric,value");
    end
    if (perf_enabled)
      $display("[PERF] timer CSR PCs: start=%08h stop=%08h; initial iterations=%0d",
               perf_start_pc, perf_stop_pc, perf_iterations);
  end

  always @* begin
    perf_events = '0;
    perf_events[P_CYC] = 1;
    perf_events[P_ARCH] = u_cpu.instret_pulse;
    perf_events[P_UNIT] = u_cpu.instret_pulse;
    perf_events[P_FUSED] = u_cpu.instret_pulse && u_cpu.instret_dbl;
    perf_events[P_BR] = perf_br_event;
    perf_events[P_BRDIR] = perf_br_event && u_cpu.predict_dir_wrong;
    perf_events[P_BRTARGET] = perf_br_event && u_cpu.predict_target_bad;
    perf_events[P_BRMIS] = perf_events[P_BRDIR] || perf_events[P_BRTARGET];
    perf_events[P_JMP] = perf_jmp_event;
    perf_events[P_JMPNOT] = perf_jmp_event && !u_cpu.e2_predict_taken;
    perf_events[P_JMPTARGET] = perf_jmp_event && u_cpu.predict_jump_bad;
    perf_events[P_JMPMIS] = perf_events[P_JMPNOT] || perf_events[P_JMPTARGET];
    perf_events[P_SPURIOUS] = u_cpu.e2_valid && u_cpu.predict_spurious && !u_cpu.stall_back;
    perf_events[P_REDIRECT] = u_cpu.predict_wrong;
    perf_events[P_DRAM] = u_cpu.dram_stall;
    perf_events[P_DEP] = u_cpu.load_use_stall;
    perf_events[P_MDU] = u_cpu.mdu_stall;
    perf_events[P_CSR] = u_cpu.csr_raw_stall;
    perf_events[P_ANY] = u_cpu.stall;
    perf_events[P_OVERLAP] =
        (integer'(u_cpu.dram_stall) + integer'(u_cpu.load_use_stall) +
         integer'(u_cpu.mdu_stall) + integer'(u_cpu.csr_raw_stall)) > 1;
    perf_events[P_E1LD] = perf_e1ld;
    perf_events[P_E1MUL] = perf_e1mul;
    perf_events[P_E2LD] = perf_e2ld;
    perf_events[P_E2MUL] = perf_e2mul;
    perf_events[P_M1LD] = perf_m1ld;
    perf_events[P_LD] = perf_ld_dep;
    perf_events[P_MUL] = perf_mul_dep;
    perf_events[P_BOTH] = perf_ld_dep && perf_mul_dep;
    perf_events[P_ANY_RUN] = u_cpu.stall && !perf_prev_any;
    perf_events[P_DEP_RUN] = u_cpu.load_use_stall && !perf_prev_dep;
    perf_events[P_LD_RUN] = perf_ld_dep && !perf_prev_ld;
    perf_events[P_MUL_RUN] = perf_mul_dep && !perf_prev_mul;
    perf_events[P_FEEMPTY] = !u_cpu.head_v && !u_cpu.stall && !u_cpu.redirect_now;
    perf_events[P_NORET] = !u_cpu.instret_pulse;
    perf_events[P_D1TRY] = perf_d1_probe;
    perf_events[P_D1HIT] = perf_d1_probe && u_cpu.d1_hit;
    perf_events[P_D1SB] = perf_events[P_D1HIT] && u_cpu.d1_sb_hit;
    perf_events[P_D1L0] = perf_events[P_D1HIT] && !u_cpu.d1_sb_hit;
    perf_events[P_D1MISS] = perf_d1_probe && !u_cpu.d1_hit;
    perf_events[P_STCONFLICT] = u_cpu.st_conflict && u_cpu.e2_mem_re && !u_cpu.stall_back;
  end

  always @(posedge clk) begin : sample_performance
    integer k;
    if (rst) begin
      perf_all = '0;
      perf_window = '0;
      perf_active = 0;
      perf_windows = 0;
      perf_boundary_errors = 0;
      perf_prev_any = 0; perf_prev_dep = 0; perf_prev_ld = 0; perf_prev_mul = 0;
    end else begin
      if (perf_start_event) begin
        if (perf_active) perf_boundary_errors = perf_boundary_errors + 1;
        perf_window = '0;
        perf_start_tick = u_cpu.csr_rdata;
        perf_active = 1;
      end
      if (perf_stop_event) begin
        if (!perf_active) perf_boundary_errors = perf_boundary_errors + 1;
        else begin
          perf_stop_tick = u_cpu.csr_rdata;
          perf_windows = perf_windows + 1;
          if (perf_window[P_CYC][31:0] != (perf_stop_tick - perf_start_tick))
            perf_boundary_errors = perf_boundary_errors + 1;
        end
        perf_active = 0;
      end
      for (k=0; k<P_COUNT; k=k+1) begin
        if (perf_events[k]) begin
          perf_all[k] = perf_all[k] + ((k == P_ARCH && u_cpu.instret_dbl) ? 64'd2 : 64'd1);
          if (perf_active)
            perf_window[k] = perf_window[k] + ((k == P_ARCH && u_cpu.instret_dbl) ? 64'd2 : 64'd1);
        end
      end
      perf_prev_any = u_cpu.stall;
      perf_prev_dep = u_cpu.load_use_stall;
      perf_prev_ld = perf_ld_dep;
      perf_prev_mul = perf_mul_dep;
    end
  end

  // Read the actual final iterations/ticks from UART as well. This also handles
  // CoreMark's automatic iteration calibration; only its final window is used.
  task automatic perf_uart_character(input byte unsigned character);
    longint unsigned value;
    string mode;
    begin
      if (character == 10) begin
        if ($sscanf(perf_uart_line, "Total ticks : %d", value) == 1) begin
          perf_reported_ticks = value;
          perf_ticks_seen = 1;
        end
        if ($sscanf(perf_uart_line, "Iterations : %d", value) == 1) begin
          perf_iterations = value;
          perf_iterations_seen = 1;
        end
        if ($sscanf(perf_uart_line, "CPU clock (Hz) : %d", value) == 1)
          perf_reported_hz = value;
        if ($sscanf(perf_uart_line, "2K %s run parameters for coremark.", mode) == 1)
          perf_run_mode = mode;
        perf_uart_line = "";
      end else if (character != 13) begin
        // Limit retained text if a program emits binary/no-newline output.
        if (perf_uart_line.len() < 4096)
          perf_uart_line = {perf_uart_line, character};
      end
    end
  endtask

  function automatic real perf_ratio(input logic [63:0] n, input logic [63:0] d);
    perf_ratio = (d == 0) ? 0.0 : real'(n) / real'(d);
  endfunction

  function automatic string perf_metric_name(input integer k);
    case (k)
      P_CYC: return "cycles"; P_ARCH: return "retired_arch_instructions";
      P_UNIT: return "retired_units"; P_FUSED: return "retired_fused_pairs";
      P_BR: return "resolved_branches"; P_BRMIS: return "branch_mispredictions";
      P_BRDIR: return "branch_direction_errors"; P_BRTARGET: return "branch_target_errors";
      P_JMP: return "resolved_jumps"; P_JMPMIS: return "jump_mispredictions";
      P_JMPNOT: return "jump_not_predicted_taken"; P_JMPTARGET: return "jump_target_errors";
      P_SPURIOUS: return "spurious_taken_predictions"; P_REDIRECT: return "prediction_redirects";
      P_DRAM: return "dram_stall_cycles"; P_DEP: return "dependency_stall_cycles";
      P_MDU: return "mdu_stall_cycles"; P_CSR: return "csr_stall_cycles";
      P_ANY: return "any_stall_cycles"; P_OVERLAP: return "overlapping_stall_cycles";
      P_LD: return "load_dependency_cycles"; P_MUL: return "mul_dependency_cycles";
      P_BOTH: return "load_and_mul_dependency_cycles";
      P_E1LD: return "ex1_load_dependency_cycles"; P_E1MUL: return "ex1_mul_dependency_cycles";
      P_E2LD: return "ex2_load_dependency_cycles"; P_E2MUL: return "ex2_mul_dependency_cycles";
      P_M1LD: return "mem1_load_dependency_cycles";
      P_ANY_RUN: return "stall_assertion_runs"; P_DEP_RUN: return "dependency_assertion_runs";
      P_LD_RUN: return "load_dependency_assertion_runs"; P_MUL_RUN: return "mul_dependency_assertion_runs";
      P_FEEMPTY: return "frontend_empty_opportunity_cycles"; P_NORET: return "no_retirement_cycles";
      P_D1TRY: return "d1_eligible_probes"; P_D1HIT: return "d1_fastpath_hits";
      P_D1SB: return "d1_storebuffer_selected"; P_D1L0: return "d1_l0_selected";
      P_D1MISS: return "d1_fastpath_misses"; P_STCONFLICT: return "store_load_conflicts";
      default: return "unknown";
    endcase
  endfunction

  task automatic print_perf_scope(input string scope, input perf_stats_t s);
    integer k;
    begin
      $display("---------------- %s ----------------", scope);
      $display(" cycles=%0d  arch_inst=%0d  retired_units=%0d  fused_pairs=%0d",
               s[P_CYC], s[P_ARCH], s[P_UNIT], s[P_FUSED]);
      $display(" CPI_arch=%.6f  cycles/retired_unit=%.6f",
               perf_ratio(s[P_CYC],s[P_ARCH]), perf_ratio(s[P_CYC],s[P_UNIT]));
      $display(" branch: resolved=%0d mispred=%0d direction=%0d target=%0d accuracy=%.2f%%",
               s[P_BR],s[P_BRMIS],s[P_BRDIR],s[P_BRTARGET],
               100.0*perf_ratio(s[P_BR]-s[P_BRMIS],s[P_BR]));
      $display(" jump: resolved=%0d mispred=%0d not_taken_prediction=%0d target=%0d accuracy=%.2f%%",
               s[P_JMP],s[P_JMPMIS],s[P_JMPNOT],s[P_JMPTARGET],
               100.0*perf_ratio(s[P_JMP]-s[P_JMPMIS],s[P_JMP]));
      $display(" prediction: redirects=%0d spurious_taken=%0d (events, not lost cycles)",
               s[P_REDIRECT],s[P_SPURIOUS]);
      $display(" stalls: any=%0d (%.3f%%) overlapping=%0d runs=%0d",
               s[P_ANY],100.0*perf_ratio(s[P_ANY],s[P_CYC]),s[P_OVERLAP],s[P_ANY_RUN]);
      $display(" stall causes: dram=%0d (%.3f%%) dependency=%0d (%.3f%%) mdu=%0d (%.3f%%) csr=%0d (%.3f%%)",
               s[P_DRAM],100.0*perf_ratio(s[P_DRAM],s[P_CYC]),
               s[P_DEP],100.0*perf_ratio(s[P_DEP],s[P_CYC]),
               s[P_MDU],100.0*perf_ratio(s[P_MDU],s[P_CYC]),
               s[P_CSR],100.0*perf_ratio(s[P_CSR],s[P_CYC]));
      $display(" dependency: load=%0d (%.3f%%) mul=%0d (%.3f%%) both=%0d",
               s[P_LD],100.0*perf_ratio(s[P_LD],s[P_CYC]),
               s[P_MUL],100.0*perf_ratio(s[P_MUL],s[P_CYC]),s[P_BOTH]);
      $display(" dependency stages: e1_load=%0d e1_mul=%0d e2_load=%0d e2_mul=%0d m1_load=%0d",
               s[P_E1LD],s[P_E1MUL],s[P_E2LD],s[P_E2MUL],s[P_M1LD]);
      $display(" dependency runs: any=%0d load=%0d mul=%0d (contiguous assertion starts)",
               s[P_DEP_RUN],s[P_LD_RUN],s[P_MUL_RUN]);
      $display(" frontend_empty_opportunity=%0d (%.3f%%) no_retirement=%0d (%.3f%%)",
               s[P_FEEMPTY],100.0*perf_ratio(s[P_FEEMPTY],s[P_CYC]),
               s[P_NORET],100.0*perf_ratio(s[P_NORET],s[P_CYC]));
      $display(" D1 eligible probes=%0d hits=%0d (%.2f%%) SB_selected=%0d L0_selected=%0d misses=%0d store_conflicts=%0d",
               s[P_D1TRY],s[P_D1HIT],100.0*perf_ratio(s[P_D1HIT],s[P_D1TRY]),
               s[P_D1SB],s[P_D1L0],s[P_D1MISS],s[P_STCONFLICT]);
      if (perf_csv) begin
        for (k=0; k<P_COUNT; k=k+1)
          $fdisplay(perf_csv,"%s,%s,%0d",scope,perf_metric_name(k),s[k]);
        $fdisplay(perf_csv,"%s,cpi_arch,%.9f",scope,perf_ratio(s[P_CYC],s[P_ARCH]));
        $fdisplay(perf_csv,"%s,cycles_per_retired_unit,%.9f",scope,perf_ratio(s[P_CYC],s[P_UNIT]));
      end
    end
  endtask

  task automatic dump_perf(input string tag);
    begin
      $display("\n================ PERFORMANCE [%s] ================", tag);
      $display(" Observer: pre-NBA CPU edges; retirement=WB, branch/jump resolution=EX2.");
      $display(" Cause counters overlap; any_stall is their union. Runs are not instruction/event counts.");
      print_perf_scope("WHOLE_PROGRAM",perf_all);
      if (perf_enabled && perf_windows > 0 && !perf_active && perf_boundary_errors == 0) begin
        print_perf_scope("COREMARK_TIMED",perf_window);
        $display(" window: last of %0d completed pairs; mcycle start=%0d stop=%0d; mode=%s",
                 perf_windows,perf_start_tick,perf_stop_tick,perf_run_mode);
        if (perf_ticks_seen) begin
          if (perf_reported_ticks == perf_window[P_CYC])
            $display(" Total ticks cross-check: MATCH (%0d)",perf_reported_ticks);
          else
            $display(" [PERF] ERROR: UART Total ticks=%0d; observed window=%0d",
                     perf_reported_ticks,perf_window[P_CYC]);
        end else $display(" Total ticks cross-check: unavailable (UART line not received).");
        if (tag == "EXIT" && perf_iterations_seen && perf_iterations > 0 &&
            perf_ticks_seen && perf_reported_ticks == perf_window[P_CYC]) begin
          $display(" iterations=%0d cycles/iteration=%.6f arch_instructions/iteration=%.6f",
                   perf_iterations,perf_ratio(perf_window[P_CYC],perf_iterations),
                   perf_ratio(perf_window[P_ARCH],perf_iterations));
          $display(" normalized throughput/MHz=%.6f (simulation estimate; validation is not a performance score)",
                   1000000.0*perf_ratio(perf_iterations,perf_window[P_CYC]));
          if (perf_csv) begin
            $fdisplay(perf_csv,"COREMARK_TIMED,iterations,%0d",perf_iterations);
            $fdisplay(perf_csv,"COREMARK_TIMED,cycles_per_iteration,%.9f",perf_ratio(perf_window[P_CYC],perf_iterations));
            $fdisplay(perf_csv,"COREMARK_TIMED,throughput_per_mhz_estimate,%.9f",1000000.0*perf_ratio(perf_iterations,perf_window[P_CYC]));
          end
        end else $display(" Per-iteration/normalized estimates withheld until final UART iterations and matching ticks are available.");
        $display(" TB clock=100000000 Hz; program-reported CPU_HZ=%0d; timed duration at TB clock=%.9f s",
                 perf_reported_hz,perf_ratio(perf_window[P_CYC],64'd100000000));
        if (perf_reported_hz != 0 && perf_reported_hz != 100000000)
          $display(" [PERF] WARNING: program CPU_HZ differs from the TB clock; UART time/score uses program CPU_HZ.");
        if (perf_window[P_CYC] >= 64'h100000000)
          $display(" [PERF] WARNING: timed interval exceeds the port's 32-bit timer range.");
      end else if (perf_active) begin
        print_perf_scope("COREMARK_PARTIAL",perf_window);
        $display(" [PERF] INCOMPLETE: stop timer read not reached; no per-iteration estimate.");
      end else begin
        $display(" [PERF] timed report unavailable: enabled=%0d completed=%0d boundary_errors=%0d",
                 perf_enabled,perf_windows,perf_boundary_errors);
      end
      $display("==================================================");
      if (perf_csv) begin
        $fdisplay(perf_csv,"METADATA,run_mode,%s",perf_run_mode);
        $fdisplay(perf_csv,"METADATA,exit_reason,%s",tag);
        $fdisplay(perf_csv,"METADATA,window_active,%0d",perf_active);
        $fdisplay(perf_csv,"METADATA,completed_timer_pairs,%0d",perf_windows);
        $fdisplay(perf_csv,"METADATA,boundary_errors,%0d",perf_boundary_errors);
        $fdisplay(perf_csv,"METADATA,uart_ticks_available,%0d",perf_ticks_seen);
        $fdisplay(perf_csv,"METADATA,uart_iterations_available,%0d",perf_iterations_seen);
        $fdisplay(perf_csv,"METADATA,uart_ticks_match,%0d",perf_ticks_seen &&
                  perf_windows > 0 && !perf_active && perf_boundary_errors == 0 &&
                  perf_reported_ticks == perf_window[P_CYC]);
        $fdisplay(perf_csv,"METADATA,uart_total_ticks,%0d",perf_reported_ticks);
        $fdisplay(perf_csv,"METADATA,program_cpu_hz,%0d",perf_reported_hz);
        $fdisplay(perf_csv,"METADATA,tb_cpu_hz,100000000");
        $fclose(perf_csv);
        perf_csv = 0;
        $display("[PERF] CSV = %s",perf_csv_path);
      end
    end
  endtask

endmodule
