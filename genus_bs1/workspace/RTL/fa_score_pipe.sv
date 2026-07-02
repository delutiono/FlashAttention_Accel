`timescale 1ns/1ps

module fa_score_pipe #(
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned SCORE_W = 48
) (
  input  logic                              clk,
  input  logic                              rst_n,
  input  logic                              valid_i,
  input  logic [7:0]                        q_index_i,
  input  logic [7:0]                        k_index_i,
  input  var logic signed [ELEM_W-1:0]      q_i [D],
  input  var logic signed [ELEM_W-1:0]      k_i [D],
  output logic                              valid_o,
  output logic [7:0]                        q_index_o,
  output logic [7:0]                        k_index_o,
  output logic signed [SCORE_W-1:0]         score_o
);
  logic dot_valid;
  logic signed [SCORE_W-1:0] dot_score;
  logic signed [SCORE_W-1:0] scaled_score;

  fa_dot_pe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .ACC_W(SCORE_W)
  ) u_dot_pe (
    .clk,
    .rst_n,
    .valid_i,
    .q_i,
    .k_i,
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
      q_index_o <= 8'h0;
      k_index_o <= 8'h0;
    end else begin
      q_index_o <= valid_i ? q_index_i : 8'h0;
      k_index_o <= valid_i ? k_index_i : 8'h0;
    end
  end

  assign valid_o = dot_valid;
  assign score_o = scaled_score;
endmodule
