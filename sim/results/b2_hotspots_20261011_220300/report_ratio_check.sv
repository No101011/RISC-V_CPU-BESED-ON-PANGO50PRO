module report_ratio_check;
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

integer perf_csv=0;
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
    logic [63:0] counts [0:P_COUNT-1];
    begin
      // ModelSim 2020.4: use inline real casts; task array function arguments are unreliable.
      for (k=0; k<P_COUNT; k=k+1) counts[k] = s[k];
      $display("---------------- %s ----------------", scope);
      $display(" cycles=%0d  arch_inst=%0d  retired_units=%0d  fused_pairs=%0d",
               counts[P_CYC], counts[P_ARCH], counts[P_UNIT], counts[P_FUSED]);
      $display(" CPI_arch=%.6f  cycles/retired_unit=%.6f",
               ((counts[P_ARCH]) == 0 ? 0.0 : real'(counts[P_CYC]) / real'(counts[P_ARCH])), ((counts[P_UNIT]) == 0 ? 0.0 : real'(counts[P_CYC]) / real'(counts[P_UNIT])));
      $display(" branch: resolved=%0d mispred=%0d direction=%0d target=%0d accuracy=%.2f%%",
               counts[P_BR],counts[P_BRMIS],counts[P_BRDIR],counts[P_BRTARGET],
               100.0*((counts[P_BR]) == 0 ? 0.0 : real'(counts[P_BR]-counts[P_BRMIS]) / real'(counts[P_BR])));
      $display(" jump: resolved=%0d mispred=%0d not_taken_prediction=%0d target=%0d accuracy=%.2f%%",
               counts[P_JMP],counts[P_JMPMIS],counts[P_JMPNOT],counts[P_JMPTARGET],
               100.0*((counts[P_JMP]) == 0 ? 0.0 : real'(counts[P_JMP]-counts[P_JMPMIS]) / real'(counts[P_JMP])));
      $display(" prediction: redirects=%0d spurious_taken=%0d (events, not lost cycles)",
               counts[P_REDIRECT],counts[P_SPURIOUS]);
      $display(" stalls: any=%0d (%.3f%%) overlapping=%0d runs=%0d",
               counts[P_ANY],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_ANY]) / real'(counts[P_CYC])),counts[P_OVERLAP],counts[P_ANY_RUN]);
      $display(" stall causes: dram=%0d (%.3f%%) dependency=%0d (%.3f%%) mdu=%0d (%.3f%%) csr=%0d (%.3f%%)",
               counts[P_DRAM],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_DRAM]) / real'(counts[P_CYC])),
               counts[P_DEP],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_DEP]) / real'(counts[P_CYC])),
               counts[P_MDU],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_MDU]) / real'(counts[P_CYC])),
               counts[P_CSR],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_CSR]) / real'(counts[P_CYC])));
      $display(" dependency: load=%0d (%.3f%%) mul=%0d (%.3f%%) both=%0d",
               counts[P_LD],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_LD]) / real'(counts[P_CYC])),
               counts[P_MUL],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_MUL]) / real'(counts[P_CYC])),counts[P_BOTH]);
      $display(" dependency stages: e1_load=%0d e1_mul=%0d e2_load=%0d e2_mul=%0d m1_load=%0d",
               counts[P_E1LD],counts[P_E1MUL],counts[P_E2LD],counts[P_E2MUL],counts[P_M1LD]);
      $display(" dependency runs: any=%0d load=%0d mul=%0d (contiguous assertion starts)",
               counts[P_DEP_RUN],counts[P_LD_RUN],counts[P_MUL_RUN]);
      $display(" frontend_empty_opportunity=%0d (%.3f%%) no_retirement=%0d (%.3f%%)",
               counts[P_FEEMPTY],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_FEEMPTY]) / real'(counts[P_CYC])),
               counts[P_NORET],100.0*((counts[P_CYC]) == 0 ? 0.0 : real'(counts[P_NORET]) / real'(counts[P_CYC])));
      $display(" D1 eligible probes=%0d hits=%0d (%.2f%%) SB_selected=%0d L0_selected=%0d misses=%0d store_conflicts=%0d",
               counts[P_D1TRY],counts[P_D1HIT],100.0*((counts[P_D1TRY]) == 0 ? 0.0 : real'(counts[P_D1HIT]) / real'(counts[P_D1TRY])),
               counts[P_D1SB],counts[P_D1L0],counts[P_D1MISS],counts[P_STCONFLICT]);
      if (perf_csv) begin
        for (k=0; k<P_COUNT; k=k+1)
          $fdisplay(perf_csv,"%s,%s,%0d",scope,perf_metric_name(k),counts[k]);
        $fdisplay(perf_csv,"%s,cpi_arch,%.9f",scope,((counts[P_ARCH]) == 0 ? 0.0 : real'(counts[P_CYC]) / real'(counts[P_ARCH])));
        $fdisplay(perf_csv,"%s,cycles_per_retired_unit,%.9f",scope,((counts[P_UNIT]) == 0 ? 0.0 : real'(counts[P_CYC]) / real'(counts[P_UNIT])));
      end
    end
  endtask
perf_stats_t data;
initial begin
data='0;
data[P_CYC] = 64'd3507488;
data[P_ARCH] = 64'd2903833;
data[P_UNIT] = 64'd2899123;
data[P_FUSED] = 64'd4710;
data[P_BR] = 64'd529588;
data[P_BRMIS] = 64'd39533;
data[P_BRDIR] = 64'd39533;
data[P_BRTARGET] = 64'd17270;
data[P_JMP] = 64'd63102;
data[P_JMPMIS] = 64'd364;
data[P_JMPNOT] = 64'd79;
data[P_JMPTARGET] = 64'd364;
data[P_SPURIOUS] = 64'd0;
data[P_REDIRECT] = 64'd39897;
data[P_DRAM] = 64'd0;
data[P_DEP] = 64'd450731;
data[P_MDU] = 64'd0;
data[P_CSR] = 64'd0;
data[P_ANY] = 64'd450731;
data[P_OVERLAP] = 64'd0;
data[P_LD] = 64'd321131;
data[P_MUL] = 64'd129600;
data[P_BOTH] = 64'd0;
data[P_E1LD] = 64'd142508;
data[P_E1MUL] = 64'd35640;
data[P_E2LD] = 64'd178623;
data[P_E2MUL] = 64'd93960;
data[P_M1LD] = 64'd0;
data[P_ANY_RUN] = 64'd274588;
data[P_DEP_RUN] = 64'd274588;
data[P_LD_RUN] = 64'd180628;
data[P_MUL_RUN] = 64'd93960;
data[P_FEEMPTY] = 64'd39897;
data[P_NORET] = 64'd608365;
data[P_D1TRY] = 64'd393163;
data[P_D1HIT] = 64'd211861;
data[P_D1SB] = 64'd53648;
data[P_D1L0] = 64'd158213;
data[P_D1MISS] = 64'd181302;
data[P_STCONFLICT] = 64'd0;
print_perf_scope("RATIO_CHECK",data);
$finish;
end
endmodule
