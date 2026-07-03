`timescale 1ns/1ps

module fa_score_pipe #(
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned SCORE_W = 48,
  parameter int unsigned DOT_LANES = fa_pkg::FA_DOT_LANES
) (
  input  logic                              clk,
  input  logic                              rst_n,
  input  logic                              valid_i,
  input  logic [7:0]                        q_index_i,
  input  logic [7:0]                        k_index_i,
  input  logic signed [ELEM_W-1:0]          q_i [D],
  input  logic signed [ELEM_W-1:0]          k_i [D],
  output logic                              ready_o,
  output logic                              valid_o,
  output logic [7:0]                        q_index_o,
  output logic [7:0]                        k_index_o,
  output logic signed [SCORE_W-1:0]         score_o
);
  localparam int unsigned DOT_LATENCY_CYCLES = (D + DOT_LANES - 1) / DOT_LANES;

  logic dot_ready;
  logic dot_valid;
  logic score_accept;
  logic signed [SCORE_W-1:0] dot_score;
  logic signed [SCORE_W-1:0] scaled_score;
  logic [7:0] q_index_pipe_q [0:DOT_LATENCY_CYCLES];
  logic [7:0] k_index_pipe_q [0:DOT_LATENCY_CYCLES];

  assign ready_o = dot_ready;
  assign score_accept = valid_i && ready_o;

  fa_dot_pe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .ACC_W(SCORE_W),
    .DOT_LANES(DOT_LANES)
  ) u_dot_pe (
    .clk,
    .rst_n,
    .valid_i(score_accept),
    .q_i,
    .k_i,
    .ready_o(dot_ready),
    .valid_o(dot_valid),
    .dot_o(dot_score)
  );

  fa_score_scale #(
    .SCORE_W(SCORE_W)
  ) u_score_scale (
    .raw_dot_i(dot_score),
    .scaled_score_o(scaled_score)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int stage = 0; stage <= DOT_LATENCY_CYCLES; stage++) begin
        q_index_pipe_q[stage] <= 8'h0;
        k_index_pipe_q[stage] <= 8'h0;
      end
    end else begin
      q_index_pipe_q[0] <= score_accept ? q_index_i : 8'h0;
      k_index_pipe_q[0] <= score_accept ? k_index_i : 8'h0;
      for (int stage = 1; stage <= DOT_LATENCY_CYCLES; stage++) begin
        q_index_pipe_q[stage] <= q_index_pipe_q[stage-1];
        k_index_pipe_q[stage] <= k_index_pipe_q[stage-1];
      end
    end
  end

  assign valid_o   = dot_valid;
  assign q_index_o = dot_valid ? q_index_pipe_q[DOT_LATENCY_CYCLES] : 8'h0;
  assign k_index_o = dot_valid ? k_index_pipe_q[DOT_LATENCY_CYCLES] : 8'h0;
  assign score_o   = dot_valid ? scaled_score : '0;
endmodule
