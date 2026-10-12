module ratio_probe;
  typedef logic [39:0][63:0] stats_t;
  stats_t counters = '0;
  function automatic real original_ratio(input logic [63:0] n, input logic [63:0] d);
    original_ratio = (d == 0) ? 0.0 : real'(n) / real'(d);
  endfunction
  function automatic real explicit_ratio(input logic [63:0] n, input logic [63:0] d);
    real nr, dr;
    begin
      nr = n;
      dr = d;
      if (d == 0) explicit_ratio = 0.0;
      else explicit_ratio = nr / dr;
    end
  endfunction
  task automatic show(input stats_t s);
    logic [63:0] n_copy, d_copy;
    real n_real, d_real;
    begin
      n_copy = s[0];
      d_copy = s[1];
      n_real = n_copy;
      d_real = d_copy;
      $display("task_counts=%0d,%0d", s[0], s[1]);
      $display("original_task_ratio=%.9f explicit_task_ratio=%.9f", original_ratio(s[0],s[1]), explicit_ratio(s[0],s[1]));
      $display("copied_task_ratio=%.9f local_real_ratio=%.9f inline_ratio=%.9f", original_ratio(n_copy,d_copy), n_real/d_real, real'(s[0])/real'(s[1]));
    end
  endtask
  initial begin
    counters[0] = 3557698;
    counters[1] = 2861378;
    $display("original_module_ratio=%.9f explicit_module_ratio=%.9f", original_ratio(counters[0],counters[1]), explicit_ratio(counters[0],counters[1]));
    show(counters);
    $finish;
  end
endmodule
