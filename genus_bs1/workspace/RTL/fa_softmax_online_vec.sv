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
  output logic                         ready_o,
  output logic                         valid_o,
  output logic signed [SCORE_W-1:0]    m_o,
  output logic [L_W-1:0]               l_o,
  output logic signed [ACC_W-1:0]      acc_o [D]
);
  localparam int unsigned DELTA_W = SCORE_W + 1;
  localparam int unsigned EXP_FRAC_W = 23;
  localparam logic [L_W-1:0] L_ONE =
      ({{(L_W-1){1'b0}}, 1'b1} << EXP_FRAC_W);

  typedef enum logic [1:0] {
    OP_FIRST,
    OP_EQUAL,
    OP_LOWER,
    OP_HIGHER
  } op_e;

  logic                         issue_seen_q;
  logic signed [SCORE_W-1:0]    issue_m_q;
  logic signed [SCORE_W-1:0]    commit_m_q;
  logic [L_W-1:0]               commit_l_q;
  logic signed [ACC_W-1:0]      commit_acc_q [D];

  logic                         metadata_valid_q;
  op_e                          metadata_op_q;
  logic signed [SCORE_W-1:0]    metadata_new_m_q;
  logic signed [15:0]           metadata_v_q [D];

  logic                         row_start_accept;
  logic                         transaction_accept;
  logic                         effective_seen;
  logic signed [SCORE_W-1:0]    effective_m;
  logic signed [DELTA_W-1:0]    score_ext;
  logic signed [DELTA_W-1:0]    effective_m_ext;
  logic signed [DELTA_W-1:0]    factor_x;
  op_e                          issue_op;
  logic signed [SCORE_W-1:0]    issue_new_m;

  logic                         factor_valid;
  logic [EXP_W-1:0]             factor;
  logic [L_W+EXP_W-1:0]         l_factor_product;
  logic [L_W-1:0]               l_scaled;
  logic signed [ACC_W+EXP_W:0]  acc_factor_product [D];
  logic signed [ACC_W+EXP_W:0]  v_factor_product [D];
  logic signed [ACC_W-1:0]      acc_scaled [D];
  logic signed [ACC_W-1:0]      v_scaled [D];
  logic signed [ACC_W-1:0]      v_weighted [D];

  assign ready_o = rst_n && (!row_start_i || !metadata_valid_q);
  assign row_start_accept = row_start_i && ready_o;
  assign transaction_accept =
      valid_i && score_valid_i && ready_o;

  assign effective_seen = issue_seen_q && !row_start_accept;
  assign effective_m = row_start_accept ? '0 : issue_m_q;
  assign score_ext = $signed({score_i[SCORE_W-1], score_i});
  assign effective_m_ext =
      $signed({effective_m[SCORE_W-1], effective_m});

  always_comb begin
    issue_op = OP_FIRST;
    issue_new_m = score_i;
    factor_x = '0;

    if (effective_seen) begin
      if (score_i == effective_m) begin
        issue_op = OP_EQUAL;
        issue_new_m = effective_m;
        factor_x = '0;
      end else if (score_i < effective_m) begin
        issue_op = OP_LOWER;
        issue_new_m = effective_m;
        factor_x = score_ext - effective_m_ext;
      end else begin
        issue_op = OP_HIGHER;
        issue_new_m = score_i;
        factor_x = effective_m_ext - score_ext;
      end
    end
  end

  fa_exp_approx #(
    .IN_W(DELTA_W),
    .OUT_W(EXP_W)
  ) u_factor (
    .clk(clk),
    .rst_n(rst_n),
    .valid_i(transaction_accept),
    .x_i(factor_x),
    .valid_o(factor_valid),
    .y_o(factor)
  );

  assign l_factor_product = commit_l_q * factor;
  assign l_scaled = l_factor_product >> EXP_FRAC_W;

  genvar g;
  generate
    for (g = 0; g < D; g++) begin : gen_lane_math
      assign acc_factor_product[g] =
          $signed(commit_acc_q[g]) * $signed({1'b0, factor});
      assign v_factor_product[g] =
          $signed({{(ACC_W-16){metadata_v_q[g][15]}}, metadata_v_q[g]}) *
          $signed({1'b0, factor});
      assign acc_scaled[g] = acc_factor_product[g] >>> EXP_FRAC_W;
      assign v_scaled[g] =
          $signed({{(ACC_W-16){metadata_v_q[g][15]}}, metadata_v_q[g]})
          <<< EXP_FRAC_W;
      assign v_weighted[g] = v_factor_product[g];
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      issue_seen_q <= 1'b0;
      issue_m_q <= '0;
      commit_m_q <= '0;
      commit_l_q <= '0;
      metadata_valid_q <= 1'b0;
      metadata_op_q <= OP_FIRST;
      metadata_new_m_q <= '0;
      valid_o <= 1'b0;
      m_o <= '0;
      l_o <= '0;
      for (int lane = 0; lane < D; lane++) begin
        commit_acc_q[lane] <= '0;
        metadata_v_q[lane] <= '0;
        acc_o[lane] <= '0;
      end
    end else begin
      valid_o <= 1'b0;

      if (row_start_accept) begin
        commit_m_q <= '0;
        commit_l_q <= '0;
        m_o <= '0;
        l_o <= '0;
        for (int lane = 0; lane < D; lane++) begin
          commit_acc_q[lane] <= '0;
          acc_o[lane] <= '0;
        end
      end else if (factor_valid) begin
        valid_o <= 1'b1;
        commit_m_q <= metadata_new_m_q;
        m_o <= metadata_new_m_q;

        case (metadata_op_q)
          OP_FIRST: begin
            commit_l_q <= L_ONE;
            l_o <= L_ONE;
            for (int lane = 0; lane < D; lane++) begin
              commit_acc_q[lane] <= v_scaled[lane];
              acc_o[lane] <= v_scaled[lane];
            end
          end

          OP_EQUAL, OP_LOWER: begin
            commit_l_q <= commit_l_q + factor;
            l_o <= commit_l_q + factor;
            for (int lane = 0; lane < D; lane++) begin
              commit_acc_q[lane] <= commit_acc_q[lane] + v_weighted[lane];
              acc_o[lane] <= commit_acc_q[lane] + v_weighted[lane];
            end
          end

          default: begin
            commit_l_q <= l_scaled + L_ONE;
            l_o <= l_scaled + L_ONE;
            for (int lane = 0; lane < D; lane++) begin
              commit_acc_q[lane] <= acc_scaled[lane] + v_scaled[lane];
              acc_o[lane] <= acc_scaled[lane] + v_scaled[lane];
            end
          end
        endcase
      end

      if (row_start_accept) begin
        issue_seen_q <= transaction_accept;
        issue_m_q <= transaction_accept ? score_i : '0;
      end else if (transaction_accept) begin
        issue_seen_q <= 1'b1;
        issue_m_q <= issue_new_m;
      end

      metadata_valid_q <= transaction_accept;
      if (transaction_accept) begin
        metadata_op_q <= issue_op;
        metadata_new_m_q <= issue_new_m;
        for (int lane = 0; lane < D; lane++) begin
          metadata_v_q[lane] <= v_i[lane];
        end
      end
    end
  end
endmodule
