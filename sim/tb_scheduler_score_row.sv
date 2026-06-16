`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_score_row;
  localparam int unsigned S = 256;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned SCORE_W = 48;

  logic clk;
  logic rst_n;
  logic start_i;
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

  logic [ELEM_W-1:0] q_mem [S * D];
  logic [ELEM_W-1:0] k_mem [S * D];
  int unsigned q0_score_count;
  bit saw_k1_masked;
  logic signed [SCORE_W-1:0] observed_score;

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

  initial begin
    $readmemh("test_vectors/test_000_Q.hex", q_mem);
    $readmemh("test_vectors/test_000_K.hex", k_mem);

    rst_n = 1'b0;
    start_i = 1'b0;
    q0_score_count = 0;
    saw_k1_masked = 1'b0;
    observed_score = '0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    start_i = 1'b1;
    @(negedge clk);
    start_i = 1'b0;

    for (int guard = 0; guard < 2000; guard++) begin
      @(posedge clk);
      #1;

      if (state_o == FA_ST_COMPUTE_TILE && q_index_o == 8'd0 &&
          k_index_o == 8'd1 && !score_valid_o) begin
        saw_k1_masked = 1'b1;
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

      if (q_index_o != 8'd0 || done_o || error_o) begin
        break;
      end
    end

    if (error_o) begin
      $fatal(1, "scheduler entered error state");
    end

    if (!saw_k1_masked) begin
      $fatal(1, "did not observe q=0 k=1 masked at scheduler output");
    end

    if (q0_score_count != 1) begin
      $fatal(1, "q=0 emitted %0d scores, expected exactly one", q0_score_count);
    end

    $display("tb_scheduler_score_row PASS q0_score=%0d", observed_score);
    $finish;
  end
endmodule
