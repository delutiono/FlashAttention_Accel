`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_softmax_finalize_row_scoreboard;
  localparam int unsigned S = 256;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned SCORE_PIPE_W = 48;
  localparam int unsigned SOFTMAX_SCORE_W = 24;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam int unsigned OUT_W = 16;

  `include "sim/include/tb_finalize_row_scoreboard.svh"

  logic clk;
  logic rst_n;
  logic start_i;
  logic row_start_i;
  logic busy_o;
  logic done_o;
  logic error_o;
  logic [31:0] cycles_o;
  fa_state_e state_o;
  logic [7:0] q_index_o;
  logic [7:0] kv_tile_o;
  logic [7:0] k_index_o;
  logic score_valid_o;

  logic signed [ELEM_W-1:0] q_vec [D];
  logic signed [ELEM_W-1:0] k_vec [D];
  logic score_valid;
  logic [7:0] score_q_index;
  logic [7:0] score_k_index;
  logic signed [SCORE_PIPE_W-1:0] score;
  logic signed [SOFTMAX_SCORE_W-1:0] softmax_score;
  logic signed [ELEM_W-1:0] v_vec [D];

  logic softmax_valid;
  logic softmax_ready;
  logic signed [SOFTMAX_SCORE_W-1:0] softmax_m;
  logic [L_W-1:0] softmax_l;
  logic signed [ACC_W-1:0] softmax_acc [D];
  logic softmax_tag_valid;
  logic softmax_tag_hold;
  logic [7:0] softmax_q_index;
  logic [7:0] softmax_k_index;

  logic finalize_valid;
  logic [L_W-1:0] finalize_l;
  logic signed [ACC_W-1:0] finalize_acc [D];
  logic finalize_valid_o;
  logic finalize_div_zero;
  logic signed [OUT_W-1:0] finalize_o_q88 [D];

  logic [ELEM_W-1:0] q_mem [S * D];
  logic [ELEM_W-1:0] k_mem [S * D];
  logic [ELEM_W-1:0] v_mem [S * D];

  string case_name;
  string q_file;
  string k_file;
  string v_file;
  string expected_file;
  string source_o_file;
  int target_q;
  int target_finalize_index;
  int expected_score_count;
  int guard_limit;
  bit parser_smoke_only;
  logic signed [SCORE_PIPE_W-1:0] expected_k1_score;
  logic signed [SOFTMAX_SCORE_W-1:0] expected_k1_softmax_score;

  int unsigned target_score_count;
  int unsigned target_softmax_count;
  int unsigned target_finalize_count;
  bit saw_target_row_start;
  bit saw_target_masked_next;
  bit compared_target_row;

  fa_scheduler dut_scheduler (
    .clk,
    .rst_n,
    .start_i,
    .soft_reset_i(1'b0),
    .done_clear_i(1'b0),
    .causal_en_i(1'b1),
    .q_base_i(64'h1000),
    .k_base_i(64'h2000),
    .v_base_i(64'h3000),
    .o_base_i(64'h4000),
    .stride_bytes_i(32'd128),
    .neg_large_i(16'h8000),
    .scale_i(16'h0100),
    .busy_o,
    .done_o,
    .error_o,
    .cycles_o,
    .state_o,
    .q_index_o,
    .kv_tile_o,
    .k_index_o,
    .score_valid_o
  );

  fa_score_pipe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .SCORE_W(SCORE_PIPE_W)
  ) dut_score (
    .clk,
    .rst_n,
    .valid_i(score_valid_o),
    .q_index_i(q_index_o),
    .k_index_i(k_index_o),
    .q_i(q_vec),
    .k_i(k_vec),
    .valid_o(score_valid),
    .q_index_o(score_q_index),
    .k_index_o(score_k_index),
    .score_o(score)
  );

  fa_softmax_online_vec #(
    .D(D),
    .SCORE_W(SOFTMAX_SCORE_W),
    .L_W(L_W),
    .ACC_W(ACC_W)
  ) dut_softmax (
    .clk,
    .rst_n,
    .valid_i(score_valid),
    .row_start_i(row_start_i),
    .score_valid_i(score_valid),
    .score_i(softmax_score),
    .v_i(v_vec),
    .ready_o(softmax_ready),
    .valid_o(softmax_valid),
    .m_o(softmax_m),
    .l_o(softmax_l),
    .acc_o(softmax_acc)
  );

  fa_finalize_vec #(
    .D(D),
    .L_W(L_W),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) dut_finalize (
    .clk,
    .rst_n,
    .valid_i(finalize_valid),
    .l_i(finalize_l),
    .acc_i(finalize_acc),
    .valid_o(finalize_valid_o),
    .div_zero_o(finalize_div_zero),
    .o_q88_o(finalize_o_q88)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  assign softmax_score = score[SOFTMAX_SCORE_W-1:0];
  assign finalize_valid = softmax_valid;
  assign finalize_l = softmax_l;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      softmax_tag_valid <= 1'b0;
      softmax_tag_hold <= 1'b0;
      softmax_q_index <= 8'h0;
      softmax_k_index <= 8'h0;
    end else if (row_start_i) begin
      softmax_tag_valid <= 1'b0;
      softmax_tag_hold <= 1'b0;
      softmax_q_index <= 8'h0;
      softmax_k_index <= 8'h0;
    end else if (score_valid) begin
      softmax_tag_valid <= 1'b1;
      softmax_tag_hold <= 1'b1;
      softmax_q_index <= score_q_index;
      softmax_k_index <= score_k_index;
    end else if (softmax_tag_hold) begin
      softmax_tag_valid <= 1'b1;
      softmax_tag_hold <= 1'b0;
    end else begin
      softmax_tag_valid <= 1'b0;
    end
  end

  always_comb begin
    for (int lane = 0; lane < D; lane++) begin
      q_vec[lane] = $signed(q_mem[q_index_o * D + lane]);
      k_vec[lane] = $signed(k_mem[k_index_o * D + lane]);
      v_vec[lane] = $signed(v_mem[score_k_index * D + lane]);
      finalize_acc[lane] = softmax_acc[lane];
    end
  end

  function automatic logic signed [SCORE_PIPE_W-1:0] ref_dot(
    input logic [7:0] q_idx,
    input logic [7:0] k_idx
  );
    logic signed [SCORE_PIPE_W-1:0] acc;
    logic signed [31:0] prod;
    begin
      acc = '0;
      for (int lane = 0; lane < D; lane++) begin
        prod = $signed(q_mem[q_idx * D + lane]) *
               $signed(k_mem[k_idx * D + lane]);
        acc += {{(SCORE_PIPE_W-32){prod[31]}}, prod};
      end
      return acc;
    end
  endfunction

  function automatic logic signed [SCORE_PIPE_W-1:0] ref_scaled_score(
    input logic [7:0] q_idx,
    input logic [7:0] k_idx
  );
    begin
      return ref_dot(q_idx, k_idx) >>> 3;
    end
  endfunction

  function automatic bit file_exists(input string path);
    int fd;
    begin
      if (path.len() == 0) begin
        return 1'b0;
      end

      fd = $fopen(path, "r");
      if (fd != 0) begin
        $fclose(fd);
        return 1'b1;
      end

      return 1'b0;
    end
  endfunction

  task automatic clear_vectors;
    begin
      for (int idx = 0; idx < S * D; idx++) begin
        q_mem[idx] = '0;
        k_mem[idx] = '0;
        v_mem[idx] = '0;
      end
    end
  endtask

  task automatic set_s4_v_lane(
    input int lane,
    input logic [ELEM_W-1:0] v0,
    input logic [ELEM_W-1:0] v1,
    input logic [ELEM_W-1:0] v2,
    input logic [ELEM_W-1:0] v3
  );
    begin
      v_mem[0 * D + lane] = v0;
      v_mem[1 * D + lane] = v1;
      v_mem[2 * D + lane] = v2;
      v_mem[3 * D + lane] = v3;
    end
  endtask

  task automatic init_row_scoreboard_s4_det_vectors;
    begin
      q_mem[3 * D + 0] = 16'sh0100;
      k_mem[0 * D + 0] = 16'sh0000;
      k_mem[1 * D + 0] = 16'shfc00;
      k_mem[2 * D + 0] = 16'shf000;
      k_mem[3 * D + 0] = 16'she000;

      set_s4_v_lane(0, 16'h0100, 16'h0200, 16'hff00, 16'h0080);
      set_s4_v_lane(1, 16'hff00, 16'h0000, 16'h0100, 16'h0200);
      set_s4_v_lane(2, 16'h0080, 16'hff80, 16'h0180, 16'hfe00);
      set_s4_v_lane(7, 16'h0040, 16'h0100, 16'h0000, 16'hff00);
      set_s4_v_lane(31, 16'hfe00, 16'hff00, 16'h0080, 16'h0400);
      set_s4_v_lane(63, 16'h0200, 16'hff80, 16'h0040, 16'h0100);
    end
  endtask

  task automatic configure_case;
    begin
      case_name = "q1_neg4";
      void'($value$plusargs("CASE=%s", case_name));

      q_file = "";
      k_file = "";
      v_file = "";
      source_o_file = "";
      target_q = 1;
      target_finalize_index = 2;
      expected_score_count = 2;
      guard_limit = 5000;
      parser_smoke_only = 1'b0;
      expected_k1_score = -48'sd262144;
      expected_k1_softmax_score = -24'sd262144;
      expected_file = "test_vectors/debug/q1_delta_neg4/pipeline_final_expected.txt";

      if (case_name == "q1_neg2") begin
        expected_k1_score = -48'sd131072;
        expected_k1_softmax_score = -24'sd131072;
        expected_file = "test_vectors/debug/q1_delta_neg2/pipeline_final_expected.txt";
      end else if (case_name == "q1_neg1p5") begin
        expected_k1_score = -48'sd98304;
        expected_k1_softmax_score = -24'sd98304;
        expected_file = "test_vectors/debug/q1_delta_neg1p5/pipeline_final_expected.txt";
      end else if (case_name == "q1_neg4") begin
        expected_k1_score = -48'sd262144;
        expected_k1_softmax_score = -24'sd262144;
        expected_file = "test_vectors/debug/q1_delta_neg4/pipeline_final_expected.txt";
      end else if (case_name == "q0_i0") begin
        target_q = 0;
        target_finalize_index = 1;
        expected_score_count = 1;
        q_file = "test_vectors/cases/causal_i0_Q.hex";
        k_file = "test_vectors/cases/causal_i0_K.hex";
        v_file = "test_vectors/cases/causal_i0_V.hex";
        expected_file = "test_vectors/debug/causal_i0/pipeline_final_expected.txt";
      end else if (case_name == "row_scoreboard_s4_det") begin
        target_q = 3;
        target_finalize_index = 4;
        expected_score_count = 4;
        q_file = "test_vectors/cases/row_scoreboard_s4_det_Q.hex";
        k_file = "test_vectors/cases/row_scoreboard_s4_det_K.hex";
        v_file = "test_vectors/cases/row_scoreboard_s4_det_V.hex";
        expected_file = "test_vectors/debug/row_scoreboard_s4_det/expected.txt";
      end else if (case_name == "random_full_row_seed20240623") begin
        target_q = 0;
        target_finalize_index = 1;
        expected_score_count = 1;
        parser_smoke_only = 1'b1;
        expected_file = "test_vectors/debug/random_full_row_seed20240623/row000_expected.txt";
        source_o_file = "test_vectors/cases/random_full_row_seed20240623_O_q88.hex";
      end else begin
        $fatal(1, "unsupported CASE='%s'", case_name);
      end

      void'($value$plusargs("Q_FILE=%s", q_file));
      void'($value$plusargs("K_FILE=%s", k_file));
      void'($value$plusargs("V_FILE=%s", v_file));
      void'($value$plusargs("EXPECTED=%s", expected_file));
      void'($value$plusargs("SOURCE_O=%s", source_o_file));
      void'($value$plusargs("TARGET_Q=%d", target_q));
      void'($value$plusargs("TARGET_FINALIZE_INDEX=%d", target_finalize_index));
      void'($value$plusargs("EXPECTED_SCORE_COUNT=%d", expected_score_count));
      void'($value$plusargs("GUARD=%d", guard_limit));
    end
  endtask

  task automatic init_case_vectors;
    bit have_q_file;
    bit have_k_file;
    bit have_v_file;
    bit use_s4_fallback;
    begin
      clear_vectors();

      have_q_file = file_exists(q_file);
      have_k_file = file_exists(k_file);
      have_v_file = file_exists(v_file);
      use_s4_fallback = (case_name == "row_scoreboard_s4_det") &&
                        !(have_q_file && have_k_file && have_v_file);

      if (q_file.len() != 0 && have_q_file && !use_s4_fallback) begin
        $readmemh(q_file, q_mem);
      end
      if (k_file.len() != 0 && have_k_file && !use_s4_fallback) begin
        $readmemh(k_file, k_mem);
      end
      if (v_file.len() != 0 && have_v_file && !use_s4_fallback) begin
        $readmemh(v_file, v_mem);
      end

      if (use_s4_fallback) begin
        init_row_scoreboard_s4_det_vectors();
      end else if (q_file.len() == 0 && k_file.len() == 0 && v_file.len() == 0) begin
        q_mem[1 * D + 0] = 16'sh0100;
        k_mem[0 * D + 0] = 16'sh0000;
        if (case_name == "q1_neg1p5") begin
          k_mem[1 * D + 0] = 16'shf400;
        end else if (case_name == "q1_neg2") begin
          k_mem[1 * D + 0] = 16'shf000;
        end else begin
          k_mem[1 * D + 0] = 16'she000;
        end

        v_mem[0 * D + 0] = 16'sh0100;
        v_mem[1 * D + 0] = 16'sh0200;

        v_mem[2 * D + 0] = 16'sh7f00;
        v_mem[2 * D + 1] = 16'sh7f00;
        v_mem[2 * D + 63] = 16'sh7f00;
      end
    end
  endtask

  task automatic check_case_preconditions;
    logic signed [SCORE_PIPE_W-1:0] k0_score;
    logic signed [SCORE_PIPE_W-1:0] k1_score;
    logic signed [SCORE_PIPE_W-1:0] k2_score;
    logic signed [SCORE_PIPE_W-1:0] k3_score;
    begin
      k0_score = ref_scaled_score(target_q[7:0], 8'd0);
      if (k0_score !== '0) begin
        $fatal(1, "%s q%0d/k0 expected score is %0d, expected 0",
               case_name, target_q, k0_score);
      end

      if (target_q == 1) begin
        k1_score = ref_scaled_score(8'd1, 8'd1);
        if (k1_score !== expected_k1_score) begin
          $fatal(1, "%s q1/k1 score=%0d expected=%0d",
                 case_name, k1_score, expected_k1_score);
        end
      end

      if (case_name == "row_scoreboard_s4_det") begin
        k1_score = ref_scaled_score(8'd3, 8'd1);
        k2_score = ref_scaled_score(8'd3, 8'd2);
        k3_score = ref_scaled_score(8'd3, 8'd3);
        if (k1_score !== -48'sd32768 ||
            k2_score !== -48'sd131072 ||
            k3_score !== -48'sd262144) begin
          $fatal(1, "%s q3 scores k1=%0d k2=%0d k3=%0d expected -32768/-131072/-262144",
                 case_name, k1_score, k2_score, k3_score);
        end
      end
    end
  endtask

  initial begin
    configure_case();
    if (parser_smoke_only) begin
      load_expected_row(expected_file);
      check_expected_row_from_flat_hex(case_name, source_o_file, target_q);
      $display("tb_scheduler_softmax_finalize_row_scoreboard PASS case=%s parser_smoke_only=1 q=%0d lanes=%0d expected=%s source_o=%s not_rtl_pass_evidence=1",
               case_name, target_q, expected_row_count, expected_file,
               source_o_file);
      $finish;
    end

    init_case_vectors();
    load_expected_row(expected_file);
    check_case_preconditions();

    rst_n = 1'b0;
    start_i = 1'b0;
    row_start_i = 1'b0;
    target_score_count = 0;
    target_softmax_count = 0;
    target_finalize_count = 0;
    saw_target_row_start = 1'b0;
    saw_target_masked_next = 1'b0;
    compared_target_row = 1'b0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    start_i = 1'b1;
    @(negedge clk);
    start_i = 1'b0;

    for (int guard = 0; guard < guard_limit; guard++) begin
      @(posedge clk);
      #1;

      row_start_i = 1'b0;
      if (!saw_target_row_start && state_o == FA_ST_COMPUTE_TILE &&
          q_index_o == target_q[7:0] && k_index_o == 8'd0 &&
          score_valid_o) begin
        row_start_i = 1'b1;
        saw_target_row_start = 1'b1;
      end

      if (state_o == FA_ST_COMPUTE_TILE && q_index_o == target_q[7:0] &&
          k_index_o == (target_q[7:0] + 8'd1) && !score_valid_o) begin
        saw_target_masked_next = 1'b1;
      end

      if (score_valid && score_q_index == target_q[7:0]) begin
        target_score_count++;

        if (score_k_index > target_q[7:0]) begin
          $fatal(1, "%s q%0d emitted masked k=%0d score=%0d",
                 case_name, target_q, score_k_index, score);
        end

        if (score_k_index == 8'd0 && score !== '0) begin
          $fatal(1, "%s q%0d k0 score=%0d expected 0",
                 case_name, target_q, score);
        end

        if (target_q == 1 && score_k_index == 8'd1) begin
          if (score !== expected_k1_score) begin
            $fatal(1, "%s q1 k1 score=%0d expected=%0d",
                   case_name, score, expected_k1_score);
          end
          if (softmax_score !== expected_k1_softmax_score) begin
            $fatal(1, "%s q1 k1 softmax_score=0x%06h expected=0x%06h",
                   case_name, softmax_score, expected_k1_softmax_score);
          end
        end
      end

      if (softmax_valid && softmax_tag_valid &&
          softmax_q_index == target_q[7:0]) begin
        target_softmax_count++;
      end

      if (finalize_valid_o && target_softmax_count > 0) begin
        if (finalize_div_zero !== 1'b0) begin
          $fatal(1, "%s unexpected divide-by-zero during finalize", case_name);
        end
        target_finalize_count++;
        if (target_finalize_count == target_finalize_index) begin
          check_expected_row(case_name, finalize_o_q88);
          compared_target_row = 1'b1;
        end else if (target_finalize_count > target_finalize_index) begin
          $fatal(1, "%s q%0d emitted extra finalize valid %0d after target %0d",
                 case_name, target_q, target_finalize_count,
                 target_finalize_index);
        end
      end

      if ((q_index_o > target_q[7:0] || done_o || error_o) &&
          target_finalize_count >= target_finalize_index) begin
        break;
      end
    end

    if (error_o) begin
      $fatal(1, "scheduler entered error state");
    end

    if (!saw_target_row_start) begin
      $fatal(1, "%s did not issue q%0d row_start pulse", case_name, target_q);
    end

    if (!saw_target_masked_next && target_q < (S - 1)) begin
      $fatal(1, "%s did not observe q%0d k%0d masked at scheduler output",
             case_name, target_q, target_q + 1);
    end

    if (target_score_count != expected_score_count) begin
      $fatal(1, "%s q%0d emitted %0d scores, expected %0d",
             case_name, target_q, target_score_count, expected_score_count);
    end

    if (target_softmax_count != expected_score_count) begin
      $fatal(1, "%s q%0d emitted %0d softmax valids, expected %0d",
             case_name, target_q, target_softmax_count, expected_score_count);
    end

    if (target_finalize_count != target_finalize_index || !compared_target_row) begin
      $fatal(1, "%s q%0d finalize count=%0d target=%0d compared=%0d",
             case_name, target_q, target_finalize_count,
             target_finalize_index, compared_target_row);
    end

    $display("tb_scheduler_softmax_finalize_row_scoreboard PASS case=%s q=%0d scores=%0d softmax=%0d finalize=%0d expected=%s",
             case_name, target_q, target_score_count, target_softmax_count,
             target_finalize_count, expected_file);
    $finish;
  end
endmodule
