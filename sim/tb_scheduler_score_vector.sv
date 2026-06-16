`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_score_vector;
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
  logic signed [SCORE_W-1:0] observed_score;

  logic [ELEM_W-1:0] q_mem [S * D];
  logic [ELEM_W-1:0] k_mem [S * D];

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
    begin
      acc = '0;
      for (int i = 0; i < D; i++) begin
        acc += $signed(q_mem[q_idx * D + i]) * $signed(k_mem[k_idx * D + i]);
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

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    start_i = 1'b1;
    @(negedge clk);
    start_i = 1'b0;

    wait (score_valid);
    #1;
    if (score_q_index !== 8'd0 || score_k_index !== 8'd0) begin
      $fatal(1, "first score index mismatch q=%0d k=%0d",
             score_q_index, score_k_index);
    end
    if (score !== ref_scaled_score(8'd0, 8'd0)) begin
      $fatal(1, "first score=%0d expected_scaled=%0d raw=%0d",
             score, ref_scaled_score(8'd0, 8'd0), ref_dot(8'd0, 8'd0));
    end
    observed_score = score;

    @(posedge clk);
    #1;
    if (score_valid) begin
      $fatal(1, "causal mask did not suppress k=1 for q=0");
    end

    $display("tb_scheduler_score_vector PASS first_score=%0d", observed_score);
    $finish;
  end
endmodule
