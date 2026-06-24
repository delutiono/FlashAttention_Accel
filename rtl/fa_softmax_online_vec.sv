`timescale 1ns/1ps

module fa_softmax_online_vec #(
  parameter int unsigned D = 64,
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
  input  var logic signed [15:0]       v_i [D],
  output logic                         valid_o,
  output logic signed [SCORE_W-1:0]    m_o,
  output logic [L_W-1:0]               l_o,
  output logic signed [ACC_W-1:0]      acc_o [D]
);
  localparam logic [L_W-1:0] L_ONE = ({{(L_W-1){1'b0}}, 1'b1} << 23);
  localparam logic [23:0] P_EXP_NEG_ONE = 24'h2f16ac;
  localparam logic signed [SCORE_W-1:0] SCORE_HALF = SCORE_W'(32'sd32768);
  localparam logic signed [SCORE_W-1:0] SCORE_ONE = SCORE_W'(32'sd65536);
  localparam logic signed [SCORE_W-1:0] SCORE_TWO = SCORE_W'(32'sd131072);
  localparam logic signed [SCORE_W-1:0] SCORE_FOUR = SCORE_W'(32'sd262144);
  localparam int unsigned EXP_LOWER_FIFO_DEPTH = 2;

  logic signed [SCORE_W-1:0] m_q;
  logic [L_W-1:0]            l_q;
  logic signed [ACC_W-1:0]   acc_q [D];
  logic                      seen_q;
  logic signed [ACC_W-1:0]   v_scaled [D];
  logic signed [ACC_W-1:0]   v_weighted_neg_one [D];
  logic signed [SCORE_W-1:0] score_delta;
  logic signed [SCORE_W-1:0] score_delta_up;
  logic                      lower_by_one;
  logic                      higher_by_one;
  logic                      lower_exp_supported;
  logic                      exp_lower_push;
  logic                      exp_lower_pop;
  logic                      exp_lower_can_push;
  logic [1:0]                exp_lower_count_q;
  logic signed [15:0]        exp_lower_v_q [EXP_LOWER_FIFO_DEPTH][D];
  logic                      exp_lower_valid_i;
  logic signed [SCORE_W-1:0] exp_lower_x_i;
  logic                      exp_lower_valid_o;
  logic [EXP_W-1:0]          exp_lower_p;
  logic [L_W-1:0]            l_scaled_neg_one;
  logic [L_W-1:0]            l_exp_lower;
  logic [L_W+24-1:0]         l_alpha_product;
  logic signed [ACC_W+25-1:0] acc_alpha_product [D];
  logic signed [ACC_W-1:0]   acc_scaled_neg_one [D];
  logic signed [ACC_W-1:0]   v_weighted_exp_lower [D];

  assign score_delta = m_q - score_i;
  assign score_delta_up = score_i - m_q;
  assign lower_by_one = (score_i < m_q) && (score_delta == SCORE_ONE);
  assign higher_by_one = (score_i > m_q) && (score_delta_up == SCORE_ONE);
  // Generic lower-delta path routes through fa_exp_approx; -1 keeps the
  // single-cycle fast path used by the existing bring-up checkpoints.
  assign lower_exp_supported =
      (score_i < m_q) && (score_delta != SCORE_ONE);
  assign exp_lower_pop = exp_lower_valid_o && (exp_lower_count_q != 0);
  assign exp_lower_can_push =
      (exp_lower_count_q < 2'd2) || exp_lower_pop;
  assign exp_lower_push =
      valid_i && score_valid_i && seen_q && lower_exp_supported &&
      exp_lower_can_push;
  assign exp_lower_valid_i = exp_lower_push;
  assign exp_lower_x_i = score_i - m_q;
  assign l_alpha_product = l_q * P_EXP_NEG_ONE;
  assign l_scaled_neg_one = l_alpha_product[L_W+24-1:23];
  assign l_exp_lower = l_q + {{(L_W-EXP_W){1'b0}}, exp_lower_p};

  fa_exp_approx #(
    .IN_W(SCORE_W),
    .OUT_W(EXP_W)
  ) u_exp_lower (
    .clk(clk),
    .rst_n(rst_n),
    .valid_i(exp_lower_valid_i),
    .x_i(exp_lower_x_i),
    .valid_o(exp_lower_valid_o),
    .y_o(exp_lower_p)
  );

  genvar g;
  generate
    for (g = 0; g < D; g++) begin : gen_lane_math
      assign v_scaled[g] = $signed({{(ACC_W-16){v_i[g][15]}}, v_i[g]}) <<< 23;
      assign v_weighted_neg_one[g] =
          $signed({{(ACC_W-16){v_i[g][15]}}, v_i[g]}) *
          $signed({{(ACC_W-25){1'b0}}, 1'b0, P_EXP_NEG_ONE});
      assign acc_alpha_product[g] =
          acc_q[g] * $signed({1'b0, P_EXP_NEG_ONE});
      assign acc_scaled_neg_one[g] = acc_alpha_product[g][ACC_W+25-1:23];
      assign v_weighted_exp_lower[g] =
          $signed({{(ACC_W-16){exp_lower_v_q[0][g][15]}}, exp_lower_v_q[0][g]}) *
          $signed({1'b0, exp_lower_p});
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_q     <= '0;
      l_q     <= '0;
      seen_q  <= 1'b0;
      exp_lower_count_q <= '0;
      valid_o <= 1'b0;
      m_o     <= '0;
      l_o     <= '0;
      for (int lane = 0; lane < D; lane++) begin
        acc_q[lane] <= '0;
        acc_o[lane] <= '0;
        for (int slot = 0; slot < EXP_LOWER_FIFO_DEPTH; slot++) begin
          exp_lower_v_q[slot][lane] <= '0;
        end
      end
    end else begin
      if (row_start_i) begin
        valid_o <= 1'b0;
        m_q    <= '0;
        l_q    <= '0;
        seen_q <= 1'b0;
        exp_lower_count_q <= '0;
        m_o    <= '0;
        l_o    <= '0;
        for (int lane = 0; lane < D; lane++) begin
          acc_q[lane] <= '0;
          acc_o[lane] <= '0;
          for (int slot = 0; slot < EXP_LOWER_FIFO_DEPTH; slot++) begin
            exp_lower_v_q[slot][lane] <= '0;
          end
        end
      end else begin
        if (exp_lower_pop && exp_lower_push) begin
          exp_lower_count_q <= exp_lower_count_q;
          for (int lane = 0; lane < D; lane++) begin
            if (exp_lower_count_q == 2'd1) begin
              exp_lower_v_q[0][lane] <= v_i[lane];
              exp_lower_v_q[1][lane] <= '0;
            end else begin
              exp_lower_v_q[0][lane] <= exp_lower_v_q[1][lane];
              exp_lower_v_q[1][lane] <= v_i[lane];
            end
          end
        end else if (exp_lower_pop) begin
          exp_lower_count_q <= exp_lower_count_q - 2'd1;
          for (int lane = 0; lane < D; lane++) begin
            exp_lower_v_q[0][lane] <= exp_lower_v_q[1][lane];
            exp_lower_v_q[1][lane] <= '0;
          end
        end else if (exp_lower_push) begin
          exp_lower_count_q <= exp_lower_count_q + 2'd1;
          for (int lane = 0; lane < D; lane++) begin
            if (exp_lower_count_q == 2'd0) begin
              exp_lower_v_q[0][lane] <= v_i[lane];
            end else begin
              exp_lower_v_q[1][lane] <= v_i[lane];
            end
          end
        end

        if (exp_lower_pop) begin
        valid_o <= 1'b1;
        m_q   <= m_q;
        l_q   <= l_exp_lower;
        m_o   <= m_q;
        l_o   <= l_exp_lower;
        for (int lane = 0; lane < D; lane++) begin
          acc_q[lane] <= acc_q[lane] + v_weighted_exp_lower[lane];
          acc_o[lane] <= acc_q[lane] + v_weighted_exp_lower[lane];
        end
        end else if (valid_i && score_valid_i) begin
        if (!seen_q) begin
          valid_o <= 1'b1;
          m_q    <= score_i;
          l_q    <= L_ONE;
          seen_q <= 1'b1;
          m_o    <= score_i;
          l_o    <= L_ONE;
          for (int lane = 0; lane < D; lane++) begin
            acc_q[lane] <= v_scaled[lane];
            acc_o[lane] <= v_scaled[lane];
          end
        end else if (score_i == m_q) begin
          valid_o <= 1'b1;
          m_q   <= m_q;
          l_q   <= l_q + L_ONE;
          m_o   <= m_q;
          l_o   <= l_q + L_ONE;
          for (int lane = 0; lane < D; lane++) begin
            acc_q[lane] <= acc_q[lane] + v_scaled[lane];
            acc_o[lane] <= acc_q[lane] + v_scaled[lane];
          end
        end else if (lower_by_one) begin
          valid_o <= 1'b1;
          m_q   <= m_q;
          l_q   <= l_q + {{(L_W-24){1'b0}}, P_EXP_NEG_ONE};
          m_o   <= m_q;
          l_o   <= l_q + {{(L_W-24){1'b0}}, P_EXP_NEG_ONE};
          for (int lane = 0; lane < D; lane++) begin
            acc_q[lane] <= acc_q[lane] + v_weighted_neg_one[lane];
            acc_o[lane] <= acc_q[lane] + v_weighted_neg_one[lane];
          end
        end else if (higher_by_one) begin
          valid_o <= 1'b1;
          m_q   <= score_i;
          l_q   <= l_scaled_neg_one + L_ONE;
          m_o   <= score_i;
          l_o   <= l_scaled_neg_one + L_ONE;
          for (int lane = 0; lane < D; lane++) begin
            acc_q[lane] <= acc_scaled_neg_one[lane] + v_scaled[lane];
            acc_o[lane] <= acc_scaled_neg_one[lane] + v_scaled[lane];
          end
        end else if (lower_exp_supported && exp_lower_can_push) begin
          valid_o <= 1'b0;
          m_o   <= m_q;
          l_o   <= l_q;
          for (int lane = 0; lane < D; lane++) begin
            acc_o[lane] <= acc_q[lane];
          end
        end else begin
          valid_o <= 1'b0;
          m_o   <= m_q;
          l_o   <= l_q;
          for (int lane = 0; lane < D; lane++) begin
            acc_o[lane] <= acc_q[lane];
          end
        end
      end else begin
        valid_o <= 1'b0;
        m_o   <= m_q;
        l_o   <= l_q;
        for (int lane = 0; lane < D; lane++) begin
          acc_o[lane] <= acc_q[lane];
        end
      end
      end
    end
  end
endmodule
