`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_softmax_scalar;
  localparam int unsigned S = 256;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned SCORE_W = 48;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;

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
  logic signed [SCORE_W-1:0] score;

  logic softmax_valid;
  logic signed [SCORE_W-1:0] softmax_m;
  logic [L_W-1:0] softmax_l;
  logic signed [ACC_W-1:0] softmax_acc;

  logic [ELEM_W-1:0] q_mem [S * D];
  logic [ELEM_W-1:0] k_mem [S * D];
  logic [ELEM_W-1:0] v_mem [S * D];

  int unsigned q0_softmax_count;
  int unsigned q0_score_count;
  bit saw_k1_masked;
  bit saw_masked_hold;
  bit saw_q0_softmax;
  bit row_start_armed;
  logic signed [SCORE_W-1:0] observed_score;
  logic signed [SCORE_W-1:0] observed_m;
  logic [L_W-1:0] observed_l;
  logic signed [ACC_W-1:0] observed_acc;

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
    .SCORE_W(SCORE_W)
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

  fa_softmax_online #(
    .SCORE_W(SCORE_W),
    .L_W(L_W),
    .ACC_W(ACC_W)
  ) dut_softmax (
    .clk,
    .rst_n,
    .valid_i(score_valid),
    .row_start_i(row_start_i),
    .score_valid_i(score_valid),
    .score_i(score),
    .v_i($signed(v_mem[score_k_index * D])),
    .valid_o(softmax_valid),
    .m_o(softmax_m),
    .l_o(softmax_l),
    .acc_o(softmax_acc)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  always_comb begin
    for (int i = 0; i < D; i++) begin
      q_vec[i] = $signed(q_mem[q_index_o * D + i]);
      k_vec[i] = $signed(k_mem[k_index_o * D + i]);
    end
  end

  function automatic logic signed [SCORE_W-1:0] ref_dot(
    input logic [7:0] q_idx,
    input logic [7:0] k_idx
  );
    logic signed [SCORE_W-1:0] acc;
    logic signed [31:0] prod;
    begin
      acc = '0;
      for (int i = 0; i < D; i++) begin
        prod = $signed(q_mem[q_idx * D + i]) * $signed(k_mem[k_idx * D + i]);
        acc += {{(SCORE_W-32){prod[31]}}, prod};
      end
      return acc;
    end
  endfunction

  function automatic logic signed [SCORE_W-1:0] ref_scaled_score(
    input logic [7:0] q_idx,
    input logic [7:0] k_idx
  );
    begin
      return ref_dot(q_idx, k_idx) >>> 3;
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] ref_v_scaled(input logic [7:0] k_idx);
    logic signed [ELEM_W-1:0] v_scalar;
    begin
      v_scalar = $signed(v_mem[k_idx * D]);
      return $signed({{(ACC_W-ELEM_W){v_scalar[ELEM_W-1]}}, v_scalar}) <<< 23;
    end
  endfunction

  initial begin
    $readmemh("test_vectors/cases/causal_i0_Q.hex", q_mem);
    $readmemh("test_vectors/cases/causal_i0_K.hex", k_mem);
    $readmemh("test_vectors/cases/causal_i0_V.hex", v_mem);

    rst_n = 1'b0;
    start_i = 1'b0;
    row_start_i = 1'b0;
    q0_softmax_count = 0;
    q0_score_count = 0;
    saw_k1_masked = 1'b0;
    saw_masked_hold = 1'b0;
    saw_q0_softmax = 1'b0;
    row_start_armed = 1'b0;
    observed_score = '0;
    observed_m = '0;
    observed_l = '0;
    observed_acc = '0;

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

      if (saw_k1_masked && !saw_masked_hold && !score_valid &&
          !softmax_valid && softmax_m == ref_scaled_score(8'd0, 8'd0) &&
          softmax_l == (32'd1 << 23) && softmax_acc == ref_v_scaled(8'd0)) begin
        saw_masked_hold = 1'b1;
      end

      if (score_valid && score_q_index == 8'd0) begin
        q0_score_count++;
        observed_score = score;

        if (score_k_index !== 8'd0) begin
          $fatal(1, "q=0 emitted masked k=%0d score=%0d",
                 score_k_index, score);
        end

        if (score !== ref_scaled_score(8'd0, 8'd0)) begin
          $fatal(1, "q=0 k=0 score=%0d expected_scaled=%0d raw=%0d",
                 score, ref_scaled_score(8'd0, 8'd0), ref_dot(8'd0, 8'd0));
        end
      end

      if (softmax_valid && score_q_index == 8'd0) begin
        q0_softmax_count++;
        saw_q0_softmax = 1'b1;
        observed_m = softmax_m;
        observed_l = softmax_l;
        observed_acc = softmax_acc;

        if (score_k_index !== 8'd0) begin
          $fatal(1, "q=0 softmax accepted masked k=%0d", score_k_index);
        end

        if (softmax_m !== ref_scaled_score(8'd0, 8'd0)) begin
          $fatal(1, "softmax m=%0d expected=%0d",
                 softmax_m, ref_scaled_score(8'd0, 8'd0));
        end

        if (softmax_l !== (32'd1 << 23)) begin
          $fatal(1, "softmax l=%0d expected=%0d", softmax_l, (32'd1 << 23));
        end

        if (softmax_acc !== ref_v_scaled(8'd0)) begin
          $fatal(1, "softmax acc=%0d expected=%0d",
                 softmax_acc, ref_v_scaled(8'd0));
        end
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

    if (!saw_masked_hold) begin
      $fatal(1, "masked k=1 changed softmax state or emitted valid");
    end

    if (q0_score_count != 1) begin
      $fatal(1, "q=0 emitted %0d scores, expected exactly one", q0_score_count);
    end

    if (q0_softmax_count != 1 || !saw_q0_softmax) begin
      $fatal(1, "q=0 softmax emitted %0d valids, expected exactly one",
             q0_softmax_count);
    end

    $display("tb_scheduler_softmax_scalar PASS score=%0d m=%0d l=%0d acc=%0d",
             observed_score, observed_m, observed_l, observed_acc);
    $finish;
  end
endmodule
