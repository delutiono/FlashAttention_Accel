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
  input  logic                         row_start_i,
  input  logic                         score_valid_i,
  input  logic signed [SCORE_W-1:0]    score_i,
  input  logic signed [15:0]           v_i,
  output logic                         valid_o,
  output logic signed [SCORE_W-1:0]    m_o,
  output logic [L_W-1:0]               l_o,
  output logic signed [ACC_W-1:0]      acc_o
);
  localparam logic [L_W-1:0] L_ONE = ({{(L_W-1){1'b0}}, 1'b1} << 23);
  localparam logic [23:0] P_EXP_NEG_ONE = 24'h2f16ac;
  localparam logic signed [SCORE_W-1:0] SCORE_ONE = SCORE_W'(32'sd65536);

  logic signed [SCORE_W-1:0] m_q;
  logic [L_W-1:0]            l_q;
  logic signed [ACC_W-1:0]   acc_q;
  logic                      seen_q;
  logic signed [ACC_W-1:0]   v_scaled;
  logic signed [ACC_W-1:0]   v_weighted_neg_one;
  logic signed [SCORE_W-1:0] score_delta;
  logic signed [SCORE_W-1:0] score_delta_up;
  logic                      lower_by_one;
  logic                      higher_by_one;
  logic [L_W-1:0]            l_scaled_neg_one;
  logic signed [ACC_W-1:0]   acc_scaled_neg_one;
  logic [L_W+24-1:0]         l_alpha_product;
  logic signed [ACC_W+25-1:0] acc_alpha_product;

  assign v_scaled = $signed({{(ACC_W-16){v_i[15]}}, v_i}) <<< 23;
  assign v_weighted_neg_one =
      $signed({{(ACC_W-16){v_i[15]}}, v_i}) *
      $signed({{(ACC_W-25){1'b0}}, 1'b0, P_EXP_NEG_ONE});
  assign score_delta = m_q - score_i;
  assign score_delta_up = score_i - m_q;
  assign lower_by_one = (score_i < m_q) && (score_delta == SCORE_ONE);
  assign higher_by_one = (score_i > m_q) && (score_delta_up == SCORE_ONE);
  assign l_alpha_product = l_q * P_EXP_NEG_ONE;
  assign l_scaled_neg_one = l_alpha_product[L_W+24-1:23];
  assign acc_alpha_product =
      acc_q * $signed({1'b0, P_EXP_NEG_ONE});
  assign acc_scaled_neg_one = acc_alpha_product[ACC_W+25-1:23];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_q     <= '0;
      l_q     <= '0;
      acc_q   <= '0;
      seen_q  <= 1'b0;
      valid_o <= 1'b0;
      m_o     <= '0;
      l_o     <= '0;
      acc_o   <= '0;
    end else begin
      if (row_start_i) begin
        valid_o <= 1'b0;
        m_q    <= '0;
        l_q    <= '0;
        acc_q  <= '0;
        seen_q <= 1'b0;
        m_o    <= '0;
        l_o    <= '0;
        acc_o  <= '0;
      end else if (valid_i && score_valid_i) begin
        if (!seen_q) begin
          valid_o <= 1'b1;
          m_q    <= score_i;
          l_q    <= L_ONE;
          acc_q  <= v_scaled;
          seen_q <= 1'b1;
          m_o    <= score_i;
          l_o    <= L_ONE;
          acc_o  <= v_scaled;
        end else if (score_i == m_q) begin
          valid_o <= 1'b1;
          m_q   <= m_q;
          l_q   <= l_q + L_ONE;
          acc_q <= acc_q + v_scaled;
          m_o   <= m_q;
          l_o   <= l_q + L_ONE;
          acc_o <= acc_q + v_scaled;
        end else if (lower_by_one) begin
          // Bring-up subset: score is exactly m-1.0 in S*.16.
          // alpha=exp(m_old-m_new)=1, p=exp(-1) in U1.23.
          valid_o <= 1'b1;
          m_q   <= m_q;
          l_q   <= l_q + {{(L_W-24){1'b0}}, P_EXP_NEG_ONE};
          acc_q <= acc_q + v_weighted_neg_one;
          m_o   <= m_q;
          l_o   <= l_q + {{(L_W-24){1'b0}}, P_EXP_NEG_ONE};
          acc_o <= acc_q + v_weighted_neg_one;
        end else if (higher_by_one) begin
          // Bring-up subset: score is exactly m+1.0 in S*.16.
          // alpha=exp(m_old-m_new)=exp(-1), p=1.0 in U1.23.
          valid_o <= 1'b1;
          m_q   <= score_i;
          l_q   <= l_scaled_neg_one + L_ONE;
          acc_q <= acc_scaled_neg_one + v_scaled;
          m_o   <= score_i;
          l_o   <= l_scaled_neg_one + L_ONE;
          acc_o <= acc_scaled_neg_one + v_scaled;
        end else begin
          // Other non-equal scores need exp/renormalization later.
          valid_o <= 1'b0;
          m_o   <= m_q;
          l_o   <= l_q;
          acc_o <= acc_q;
        end
      end else begin
        valid_o <= 1'b0;
        m_o   <= m_q;
        l_o   <= l_q;
        acc_o <= acc_q;
      end
    end
  end

  logic unused_exp_w;
  assign unused_exp_w = ^EXP_W;
endmodule
