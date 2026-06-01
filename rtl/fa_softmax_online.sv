`timescale 1ns/1ps

module fa_softmax_online #(
  parameter int unsigned SCORE_W = 24,
  parameter int unsigned EXP_W = 24,
  parameter int unsigned L_W = 32,
  parameter int unsigned ACC_W = 48
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         valid_i,
  input  logic                         score_valid_i,
  input  logic signed [SCORE_W-1:0]    score_i,
  input  logic signed [15:0]           v_i,
  output logic                         valid_o,
  output logic signed [SCORE_W-1:0]    m_o,
  output logic [L_W-1:0]               l_o,
  output logic signed [ACC_W-1:0]      acc_o
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      m_o     <= '0;
      l_o     <= '0;
      acc_o   <= '0;
    end else begin
      valid_o <= valid_i & score_valid_i;
      m_o     <= score_i;
      l_o     <= '0;
      acc_o   <= {{(ACC_W-16){v_i[15]}}, v_i};
    end
  end

  logic unused_exp_w;
  assign unused_exp_w = ^EXP_W;
endmodule
