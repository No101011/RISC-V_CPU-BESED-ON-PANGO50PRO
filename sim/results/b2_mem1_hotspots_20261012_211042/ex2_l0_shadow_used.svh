// Included inside tb_myCPU: read-only, pre-NBA observation of an additional
// EX2 actual-address L0 port. Never changes the DUT or its cache contents.
`include "defines.vh"
  localparam S_PROBE=0, S_WORD=1, S_HALF=2, S_BYTE=3, S_RAW=4,
      S_INVALID=5, S_TAGMISS=6, S_M1BLOCK=7, S_WBBLOCK=8, S_GUARDED=9,
      S_BAD=10, S_SAFE=11, S_DEP=12, S_DEPRAW=13, S_DEPSAFE=14,
      S_RELEASE=15, S_RELWORD=16, S_RELHALF=17, S_RELBYTE=18,
      S_CONSUMER=19, S_OTHERBLOCK=20, S_UNALIGNED=21,
      S_SBSAFE=22, S_SBONLYREL=23, S_UNIONREL=24, S_RAWBAD=25,
      S_COUNT=26;
  longint unsigned shadow_count [0:S_COUNT-1][0:IROM_WORDS-1];
  bit shadow_enabled = 0;
  integer shadow_csv = 0;
  string shadow_csv_path;

  function automatic string shadow_name(input integer k);
    case (k)
      S_PROBE: return "ex2_dram_aligned_probes";
      S_WORD: return "ex2_word_probes";
      S_HALF: return "ex2_half_probes";
      S_BYTE: return "ex2_byte_probes";
      S_RAW: return "l0_raw_hits";
      S_INVALID: return "l0_invalid_misses";
      S_TAGMISS: return "l0_tag_misses";
      S_M1BLOCK: return "l0_raw_hits_blocked_mem1_store";
      S_WBBLOCK: return "l0_raw_hits_blocked_wb_store";
      S_GUARDED: return "l0_guarded_hits";
      S_BAD: return "l0_guarded_data_mismatches";
      S_SAFE: return "l0_safe_validated_hits";
      S_DEP: return "ex2_load_dependency_cycles";
      S_DEPRAW: return "l0_raw_hits_with_ex2_dependency";
      S_DEPSAFE: return "l0_safe_hits_with_ex2_dependency";
      S_RELEASE: return "l0_releasable_cycles";
      S_RELWORD: return "l0_releasable_word_cycles";
      S_RELHALF: return "l0_releasable_half_cycles";
      S_RELBYTE: return "l0_releasable_byte_cycles";
      S_CONSUMER: return "l0_releasable_consumer_cycles";
      S_OTHERBLOCK: return "l0_safe_dependency_other_block_cycles";
      S_UNALIGNED: return "ex2_dram_unaligned_probes";
      S_SBSAFE: return "shadow_store_buffer_safe_hits";
      S_SBONLYREL: return "store_buffer_only_releasable_cycles";
      S_UNIONREL: return "l0_or_store_buffer_releasable_cycles";
      S_RAWBAD: return "l0_raw_data_mismatches";
      default: return "unknown";
    endcase
  endfunction

  task automatic shadow_reset;
    integer k, p;
    if (shadow_enabled)
      for (k=0; k<S_COUNT; k=k+1)
        for (p=0; p<IROM_WORDS; p=p+1) shadow_count[k][p] = 0;
  endtask

  task automatic shadow_add(input integer k, input logic [31:0] pc);
    if (pc >= 32'h80000000 && pc < 32'h80008000 && pc[1:0] == 0)
      shadow_count[k][pc[14:2]] = shadow_count[k][pc[14:2]] + 1;
    else $fatal(1, "EX2 shadow PC outside IROM: %08h", pc);
  endtask

  function automatic [31:0] shadow_format(input [31:0] word);
    reg [31:0] aligned;
    begin
      aligned = read_align(word, u_cpu.e2_mem_width, u_cpu.e2_alu_out[1:0]);
      case (u_cpu.e2_mem_width)
        2'b00: shadow_format = u_cpu.e2_mem_sign ?
                    {{24{aligned[7]}},aligned[7:0]} : aligned;
        2'b01: shadow_format = u_cpu.e2_mem_sign ?
                    {{16{aligned[15]}},aligned[15:0]} : aligned;
        default: shadow_format = aligned;
      endcase
    end
  endfunction

  task automatic shadow_sample;
    integer idx, b;
    reg aligned, raw_hit, mem1_store, wb_store, guarded, equal_data;
    reg safe_hit, sb_safe, other_block, may_release;
    reg [15:0] word_addr;
    reg [3:0] need;
    reg [31:0] expected, cached;
    if (shadow_enabled && u_cpu.e2_valid && u_cpu.e2_mem_re &&
        !u_cpu.stall_back && u_cpu.e2_alu_out >= DRAM_BASE &&
        u_cpu.e2_alu_out < DRAM_BASE + 32'h00020000) begin
      aligned = (u_cpu.e2_mem_width == 2'b00) ||
                (u_cpu.e2_mem_width == 2'b01 && u_cpu.e2_alu_out[0] == 0) ||
                (u_cpu.e2_mem_width == 2'b10 && u_cpu.e2_alu_out[1:0] == 0);
      if (!aligned) shadow_add(S_UNALIGNED, u_cpu.e2_pc);
      else begin
        word_addr = u_cpu.e2_alu_out[17:2];
        idx = word_addr[6:0];
        need = byte_enable(u_cpu.e2_mem_width, u_cpu.e2_alu_out[1:0]);
        expected = shadow_format(dram_mem[u_cpu.e2_alu_out[16:2]]);
        cached = shadow_format(u_cpu.u_l0.data_mem[idx]);
        raw_hit = (u_cpu.u_l0.vld[idx] === 1'b1) &&
                  (u_cpu.u_l0.tag_mem[idx] === word_addr[15:7]);
        mem1_store = u_cpu.m1_mem_we && u_cpu.dram_range &&
                     u_cpu.m1_alu_out[17:2] == word_addr;
        // The L0 update is one edge later than the actual MEM1 memory write.
        // WB store must also block, including subword invalidation pending.
        wb_store = u_cpu.w_mem_we_r && u_cpu.w_drange_r &&
                   u_cpu.w_alu_out[17:2] == word_addr;
        guarded = raw_hit && !mem1_store && !wb_store;
        equal_data = !$isunknown(expected) && (cached === expected);
        safe_hit = guarded && equal_data;
        // Optional comparison: existing four-entry SB queried without the
        // word-only EX2 enable. This is NOT counted as an L0-port benefit.
        sb_safe = 0;
`ifdef SUBWORD_FAST
        for (b=0; b<4; b=b+1)
          if (u_cpu.u_sb.mask[b] != 0 && u_cpu.u_sb.addr[b] == word_addr &&
              ((need & ~u_cpu.u_sb.mask[b]) == 0) && !mem1_store &&
              !$isunknown(expected) &&
              (shadow_format(u_cpu.u_sb.data[b]) === expected)) sb_safe = 1;
`endif
        // Removing EX2 load waiting must release the real ID consumer, not
        // merely change one dependency term while another stall/flush wins.
        other_block = perf_e1ld || perf_e1mul || perf_e2mul || perf_m1ld ||
                      u_cpu.dram_stall || u_cpu.mdu_stall || u_cpu.csr_raw_stall ||
                      u_cpu.redirect_now || !u_cpu.head_v;
        may_release = perf_e2ld && u_cpu.load_use_stall && !other_block;
        shadow_add(S_PROBE, u_cpu.e2_pc);
        shadow_add(u_cpu.e2_mem_width == 2'b10 ? S_WORD :
                   u_cpu.e2_mem_width == 2'b01 ? S_HALF : S_BYTE, u_cpu.e2_pc);
        if (raw_hit) begin
          shadow_add(S_RAW, u_cpu.e2_pc);
          if (!equal_data) shadow_add(S_RAWBAD, u_cpu.e2_pc);
          if (mem1_store) shadow_add(S_M1BLOCK, u_cpu.e2_pc);
          if (wb_store) shadow_add(S_WBBLOCK, u_cpu.e2_pc);
        end else shadow_add(u_cpu.u_l0.vld[idx] === 1'b1 ? S_TAGMISS : S_INVALID, u_cpu.e2_pc);
        if (guarded) shadow_add(S_GUARDED, u_cpu.e2_pc);
        if (guarded && !equal_data) shadow_add(S_BAD, u_cpu.e2_pc);
        if (safe_hit) shadow_add(S_SAFE, u_cpu.e2_pc);
        if (sb_safe) shadow_add(S_SBSAFE, u_cpu.e2_pc);
        if (perf_e2ld) begin
          shadow_add(S_DEP, u_cpu.e2_pc);
          if (raw_hit) shadow_add(S_DEPRAW, u_cpu.e2_pc);
          if (safe_hit) shadow_add(S_DEPSAFE, u_cpu.e2_pc);
          if (safe_hit && other_block) shadow_add(S_OTHERBLOCK, u_cpu.e2_pc);
        end
        if (may_release && safe_hit) begin
          shadow_add(S_RELEASE, u_cpu.e2_pc);
          shadow_add(u_cpu.e2_mem_width == 2'b10 ? S_RELWORD :
                     u_cpu.e2_mem_width == 2'b01 ? S_RELHALF : S_RELBYTE, u_cpu.e2_pc);
          shadow_add(S_CONSUMER, u_cpu.d_pc);
        end
        if (may_release && sb_safe && !safe_hit) shadow_add(S_SBONLYREL, u_cpu.e2_pc);
        if (may_release && (safe_hit || sb_safe)) shadow_add(S_UNIONREL, u_cpu.e2_pc);
      end
    end
  endtask

  task automatic shadow_dump;
    integer k, p;
    longint unsigned total;
    if (shadow_csv) begin
      for (k=0; k<S_COUNT; k=k+1) begin
        total = 0;
        for (p=0; p<IROM_WORDS; p=p+1) begin
          total = total + shadow_count[k][p];
          if (shadow_count[k][p] != 0)
            $fdisplay(shadow_csv, "COREMARK_TIMED,%s,%08h,%0d",
                      shadow_name(k), 32'h80000000 + 4*p, shadow_count[k][p]);
        end
        $display("[EX2_SHADOW] %s=%0d", shadow_name(k), total);
      end
      $fclose(shadow_csv);
      shadow_csv = 0;
      $display("[EX2_SHADOW] CSV = %s", shadow_csv_path);
    end
  endtask

  initial begin
    if ($value$plusargs("EX2_SHADOW_CSV=%s", shadow_csv_path)) begin
      shadow_csv = $fopen(shadow_csv_path, "w");
      if (!shadow_csv) $fatal(1, "Cannot open EX2 shadow CSV: %s", shadow_csv_path);
      shadow_enabled = 1;
      $fdisplay(shadow_csv, "scope,metric,pc,value");
      $display("[EX2_SHADOW] Observer enabled; no DUT controls are changed");
    end
  end
