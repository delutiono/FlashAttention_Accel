`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_softmax_finalize_vec;
  localparam int unsigned S = 256;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned SCORE_PIPE_W = 48;
  localparam int unsigned SOFTMAX_SCORE_W = 24;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam int unsigned OUT_W = 16;
  localparam logic [L_W-1:0] L_ONE = 32'd1 << 23;

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
  logic signed [SOFTMAX_SCORE_W-1:0] softmax_m;
  logic [L_W-1:0] softmax_l;
  logic signed [ACC_W-1:0] softmax_acc [D];

  logic finalize_valid;
  logic [L_W-1:0] finalize_l;
  logic signed [ACC_W-1:0] finalize_acc [D];
  logic finalize_valid_o;
  logic signed [OUT_W-1:0] finalize_o_q88 [D];

  logic [ELEM_W-1:0] q_mem [S * D];
  logic [ELEM_W-1:0] k_mem [S * D];
  logic [ELEM_W-1:0] v_mem [S * D];

  int unsigned q0_score_count;
  int unsigned q0_softmax_count;
  int unsigned q0_finalize_count;
  bit saw_k1_masked;
  bit saw_masked_softmax_hold;
  bit saw_q0_softmax;
  bit saw_q0_finalize;
  bit row_start_armed;
  logic signed [OUT_W-1:0] observed_o00;
  logic signed [OUT_W-1:0] observed_o01;
  logic signed [OUT_W-1:0] observed_o02;
  logic signed [OUT_W-1:0] observed_o63;

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
    .o_q88_o(finalize_o_q88)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  assign softmax_score = score[SOFTMAX_SCORE_W-1:0];
  assign finalize_valid = softmax_valid;
  assign finalize_l = softmax_l;

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

  function automatic logic signed [ACC_W-1:0] ref_v_scaled(
    input logic [7:0] k_idx,
    input int unsigned lane
  );
    logic signed [ELEM_W-1:0] v_lane;
    begin
      v_lane = $signed(v_mem[k_idx * D + lane]);
      return $signed({{(ACC_W-ELEM_W){v_lane[ELEM_W-1]}}, v_lane}) <<< 23;
    end
  endfunction

  task automatic check_softmax_lane(
    input string tag,
    input int unsigned lane,
    input logic signed [ACC_W-1:0] expected
  );
    begin
      if (softmax_acc[lane] !== expected) begin
        $fatal(1, "%s softmax lane%0d acc=0x%012h expected=0x%012h",
               tag, lane, softmax_acc[lane], expected);
      end
    end
  endtask

  task automatic check_q0_softmax_state(input string tag);
    begin
      if (softmax_m !== '0) begin
        $fatal(1, "%s softmax m=%0d expected=0", tag, softmax_m);
      end

      if (softmax_l !== L_ONE) begin
        $fatal(1, "%s softmax l=0x%08h expected=0x%08h",
               tag, softmax_l, L_ONE);
      end

      check_softmax_lane(tag, 0, ref_v_scaled(8'd0, 0));
      check_softmax_lane(tag, 1, ref_v_scaled(8'd0, 1));
      check_softmax_lane(tag, 2, ref_v_scaled(8'd0, 2));
      check_softmax_lane(tag, 63, ref_v_scaled(8'd0, 63));
    end
  endtask

  task automatic check_finalize_lane(
    input string tag,
    input int unsigned lane,
    input logic signed [OUT_W-1:0] expected
  );
    begin
      if (finalize_o_q88[lane] !== expected) begin
        $fatal(1, "%s finalize lane%0d o_q88=0x%04h expected=0x%04h",
               tag, lane, finalize_o_q88[lane], expected);
      end
    end
  endtask

  task automatic check_q0_finalize_state(input string tag);
    begin
      check_finalize_lane(tag, 0, 16'sh0100);
      check_finalize_lane(tag, 1, 16'shff00);
      check_finalize_lane(tag, 2, 16'sh0080);
      check_finalize_lane(tag, 63, 16'sh0000);
    end
  endtask

  initial begin
    logic signed [SCORE_PIPE_W-1:0] expected_score;

    $readmemh("test_vectors/cases/causal_i0_Q.hex", q_mem);
    $readmemh("test_vectors/cases/causal_i0_K.hex", k_mem);
    $readmemh("test_vectors/cases/causal_i0_V.hex", v_mem);

    rst_n = 1'b0;
    start_i = 1'b0;
    row_start_i = 1'b0;
    q0_score_count = 0;
    q0_softmax_count = 0;
    q0_finalize_count = 0;
    saw_k1_masked = 1'b0;
    saw_masked_softmax_hold = 1'b0;
    saw_q0_softmax = 1'b0;
    saw_q0_finalize = 1'b0;
    row_start_armed = 1'b0;
    observed_o00 = '0;
    observed_o01 = '0;
    observed_o02 = '0;
    observed_o63 = '0;
    expected_score = ref_scaled_score(8'd0, 8'd0);

    if (expected_score !== '0) begin
      $fatal(1, "test vector q0/k0 expected score is %0d, expected 0",
             expected_score);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    start_i = 1'b1;
    @(negedge clk);
    start_i = 1'b0;

    for (int guard = 0; guard < 2000; guard++) begin
      @(posedge clk);
      #1;

      row_start_i = 1'b0;
      if (!row_start_armed && state_o == FA_ST_COMPUTE_TILE &&
          q_index_o == 8'd0 && k_index_o == 8'd0 && score_valid_o) begin
        row_start_i = 1'b1;
        row_start_armed = 1'b1;
      end

      if (state_o == FA_ST_COMPUTE_TILE && q_index_o == 8'd0 &&
          k_index_o == 8'd1 && !score_valid_o) begin
        saw_k1_masked = 1'b1;
      end

      if (saw_k1_masked && !saw_masked_softmax_hold && !score_valid &&
          !softmax_valid) begin
        check_q0_softmax_state("masked_k1_hold");
        saw_masked_softmax_hold = 1'b1;
      end

      if (score_valid && score_q_index == 8'd0) begin
        q0_score_count++;

        if (score_k_index !== 8'd0) begin
          $fatal(1, "q=0 emitted masked k=%0d score=%0d",
                 score_k_index, score);
        end

        if (score !== expected_score) begin
          $fatal(1, "q=0 k=0 score=%0d expected=%0d raw=%0d",
                 score, expected_score, ref_dot(8'd0, 8'd0));
        end
      end

      if (softmax_valid && score_q_index == 8'd0) begin
        q0_softmax_count++;
        saw_q0_softmax = 1'b1;

        if (score_k_index !== 8'd0) begin
          $fatal(1, "q=0 softmax accepted masked k=%0d", score_k_index);
        end

        check_q0_softmax_state("q0_k0");
      end

      if (finalize_valid_o) begin
        q0_finalize_count++;
        saw_q0_finalize = 1'b1;
        observed_o00 = finalize_o_q88[0];
        observed_o01 = finalize_o_q88[1];
        observed_o02 = finalize_o_q88[2];
        observed_o63 = finalize_o_q88[63];
        check_q0_finalize_state("q0_finalize");
      end

      if (q_index_o != 8'd0 || done_o || error_o) begin
        break;
      end
    end

    if (error_o) begin
      $fatal(1, "scheduler entered error state");
    end

    if (!row_start_armed) begin
      $fatal(1, "did not issue q=0 row_start pulse");
    end

    if (!saw_k1_masked) begin
      $fatal(1, "did not observe q=0 k=1 masked at scheduler output");
    end

    if (!saw_masked_softmax_hold) begin
      $fatal(1, "masked k=1 changed softmax state or emitted valid");
    end

    if (q0_score_count != 1) begin
      $fatal(1, "q=0 emitted %0d scores, expected exactly one",
             q0_score_count);
    end

    if (q0_softmax_count != 1 || !saw_q0_softmax) begin
      $fatal(1, "q=0 softmax emitted %0d valids, expected exactly one",
             q0_softmax_count);
    end

    if (q0_finalize_count != 1 || !saw_q0_finalize) begin
      $fatal(1, "q=0 finalize emitted %0d valids, expected exactly one",
             q0_finalize_count);
    end

    $display("tb_scheduler_softmax_finalize_vec PASS score=%0d l=0x%08h o00=0x%04h o01=0x%04h o02=0x%04h o63=0x%04h",
             expected_score, softmax_l, observed_o00, observed_o01,
             observed_o02, observed_o63);
    $finish;
  end
endmodule
