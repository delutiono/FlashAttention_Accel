`timescale 1ns/1ps

module fa_group_engine #(
  parameter int unsigned D = fa_pkg::FA_D,
  parameter int unsigned GROUP_ROWS = fa_pkg::FA_Q_GROUP_ROWS,
  parameter int unsigned ELEM_W = fa_pkg::FA_ELEM_W,
  parameter int unsigned SCORE_PIPE_W = 48,
  parameter int unsigned SOFTMAX_SCORE_W = 24,
  parameter int unsigned EXP_W = 24,
  parameter int unsigned L_W = 32,
  parameter int unsigned ACC_W = 48,
  parameter int unsigned OUT_W = ELEM_W
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         init_valid_i,
  output logic                         init_ready_o,
  input  logic [2:0]                   init_context_i,
  input  logic                         score_valid_i,
  output logic                         score_ready_o,
  input  logic [2:0]                   score_context_i,
  input  logic [7:0]                   q_index_i,
  input  logic [7:0]                   k_index_i,
  input  logic                         score_last_i,
  input  var logic signed [ELEM_W-1:0] q_i [D],
  input  var logic signed [ELEM_W-1:0] k_i [D],
  input  var logic signed [ELEM_W-1:0] v_i [D],
  output logic                         context_done_valid_o,
  output logic [2:0]                   context_done_o,
  output logic                         final_valid_o,
  output logic [2:0]                   final_context_o,
  output logic                         div_zero_o,
  output logic signed [ELEM_W-1:0]     final_o [D]
);
  localparam int unsigned DELTA_W = SOFTMAX_SCORE_W + 1;
  localparam int unsigned EXP_FRAC_W = 23;
  localparam logic [L_W-1:0] L_ONE =
      ({{(L_W-1){1'b0}}, 1'b1} << EXP_FRAC_W);
  localparam int unsigned FINAL_CONTEXT_LATENCY = 5;
  localparam int unsigned SCORE_PIPE_LATENCY = 2;

  typedef enum logic [1:0] {
    OP_FIRST,
    OP_EQUAL,
    OP_LOWER,
    OP_HIGHER
  } op_e;

  logic [GROUP_ROWS-1:0] pending_q;
  logic [GROUP_ROWS-1:0] seen_q;
  logic signed [SOFTMAX_SCORE_W-1:0] m_q [GROUP_ROWS];
  logic [L_W-1:0] l_q [GROUP_ROWS];
  logic signed [ACC_W-1:0] acc_q [GROUP_ROWS][D];

  logic score_accept;
  logic score_pipe_valid;
  logic signed [SCORE_PIPE_W-1:0] score_pipe_score;
  logic signed [SOFTMAX_SCORE_W-1:0] score_pipe_score_narrow;

  logic [2:0] score_context_pipe_q [0:SCORE_PIPE_LATENCY];
  logic score_last_pipe_q [0:SCORE_PIPE_LATENCY];
  logic signed [ELEM_W-1:0] score_v_pipe_q [0:SCORE_PIPE_LATENCY][D];

  logic [2:0] update_context_q;
  logic update_last_q;
  op_e update_op_q;
  logic signed [SOFTMAX_SCORE_W-1:0] update_new_m_q;
  logic signed [ELEM_W-1:0] update_v_q [D];

  logic signed [DELTA_W-1:0] score_ext;
  logic signed [DELTA_W-1:0] m_ext;
  logic signed [DELTA_W-1:0] factor_x;
  op_e issue_op;
  logic signed [SOFTMAX_SCORE_W-1:0] issue_new_m;

  logic exp_valid;
  logic [EXP_W-1:0] factor;

  logic [L_W+EXP_W-1:0] l_factor_product;
  logic [L_W-1:0] l_scaled;
  logic signed [ACC_W+EXP_W:0] acc_factor_product [D];
  logic signed [ACC_W+EXP_W:0] v_factor_product [D];
  logic signed [ACC_W-1:0] acc_scaled [D];
  logic signed [ACC_W-1:0] v_scaled [D];
  logic signed [ACC_W-1:0] v_weighted [D];
  logic [L_W-1:0] commit_l_next;
  logic signed [ACC_W-1:0] commit_acc_next [D];

  logic finalize_valid_i;
  logic finalize_valid;
  logic [2:0] final_context_pipe [FINAL_CONTEXT_LATENCY];

  assign init_ready_o = rst_n && !pending_q[init_context_i];

  // 同一个 context 的 m/l/acc 是读改写状态，必须等上一个 update 提交后再发下一个 score。
  assign score_ready_o = rst_n && !pending_q[score_context_i];
  assign score_accept = score_valid_i && score_ready_o;
  assign score_pipe_score_narrow = score_pipe_score[SOFTMAX_SCORE_W-1:0];

  fa_score_pipe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .SCORE_W(SCORE_PIPE_W)
  ) u_score_pipe (
    .clk,
    .rst_n,
    .valid_i(score_accept),
    .q_index_i,
    .k_index_i,
    .q_i,
    .k_i,
    .valid_o(score_pipe_valid),
    .q_index_o(),
    .k_index_o(),
    .score_o(score_pipe_score)
  );

  always_comb begin
    issue_op = OP_FIRST;
    issue_new_m = score_pipe_score_narrow;
    factor_x = '0;
    score_ext = $signed({score_pipe_score_narrow[SOFTMAX_SCORE_W-1], score_pipe_score_narrow});
    m_ext = $signed({m_q[score_context_pipe_q[SCORE_PIPE_LATENCY]][SOFTMAX_SCORE_W-1],
                     m_q[score_context_pipe_q[SCORE_PIPE_LATENCY]]});

    if (seen_q[score_context_pipe_q[SCORE_PIPE_LATENCY]]) begin
      if (score_pipe_score_narrow == m_q[score_context_pipe_q[SCORE_PIPE_LATENCY]]) begin
        issue_op = OP_EQUAL;
        issue_new_m = m_q[score_context_pipe_q[SCORE_PIPE_LATENCY]];
        factor_x = '0;
      end else if (score_pipe_score_narrow < m_q[score_context_pipe_q[SCORE_PIPE_LATENCY]]) begin
        issue_op = OP_LOWER;
        issue_new_m = m_q[score_context_pipe_q[SCORE_PIPE_LATENCY]];
        factor_x = score_ext - m_ext;
      end else begin
        issue_op = OP_HIGHER;
        issue_new_m = score_pipe_score_narrow;
        factor_x = m_ext - score_ext;
      end
    end
  end

  fa_exp_approx #(
    .IN_W(DELTA_W),
    .OUT_W(EXP_W)
  ) u_factor (
    .clk,
    .rst_n,
    .valid_i(score_pipe_valid),
    .x_i(factor_x),
    .valid_o(exp_valid),
    .y_o(factor)
  );

  assign l_factor_product = l_q[update_context_q] * factor;
  assign l_scaled = l_factor_product >> EXP_FRAC_W;

  genvar lane_g;
  generate
    for (lane_g = 0; lane_g < D; lane_g++) begin : gen_update_lane
      assign acc_factor_product[lane_g] =
          $signed(acc_q[update_context_q][lane_g]) * $signed({1'b0, factor});
      assign v_factor_product[lane_g] =
          $signed({{(ACC_W-ELEM_W){update_v_q[lane_g][ELEM_W-1]}}, update_v_q[lane_g]}) *
          $signed({1'b0, factor});
      assign acc_scaled[lane_g] = acc_factor_product[lane_g] >>> EXP_FRAC_W;
      assign v_scaled[lane_g] =
          $signed({{(ACC_W-ELEM_W){update_v_q[lane_g][ELEM_W-1]}}, update_v_q[lane_g]})
          <<< EXP_FRAC_W;
      assign v_weighted[lane_g] = v_factor_product[lane_g];
    end
  endgenerate

  always_comb begin
    commit_l_next = l_q[update_context_q];
    for (int lane = 0; lane < D; lane++) begin
      commit_acc_next[lane] = acc_q[update_context_q][lane];
    end

    unique case (update_op_q)
      OP_FIRST: begin
        commit_l_next = L_ONE;
        for (int lane = 0; lane < D; lane++) begin
          commit_acc_next[lane] = v_scaled[lane];
        end
      end

      OP_EQUAL, OP_LOWER: begin
        commit_l_next = l_q[update_context_q] + factor;
        for (int lane = 0; lane < D; lane++) begin
          commit_acc_next[lane] = acc_q[update_context_q][lane] + v_weighted[lane];
        end
      end

      default: begin
        commit_l_next = l_scaled + L_ONE;
        for (int lane = 0; lane < D; lane++) begin
          commit_acc_next[lane] = acc_scaled[lane] + v_scaled[lane];
        end
      end
    endcase
  end

  assign finalize_valid_i = exp_valid && update_last_q;

  fa_finalize_vec #(
    .D(D),
    .L_W(L_W),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) u_finalize (
    .clk,
    .rst_n,
    .valid_i(finalize_valid_i),
    .l_i(commit_l_next),
    .acc_i(commit_acc_next),
    .valid_o(finalize_valid),
    .div_zero_o,
    .o_q88_o(final_o)
  );

  assign final_valid_o = finalize_valid;
  assign final_context_o = final_context_pipe[FINAL_CONTEXT_LATENCY-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_q <= '0;
      seen_q <= '0;
      update_context_q <= '0;
      update_last_q <= 1'b0;
      update_op_q <= OP_FIRST;
      update_new_m_q <= '0;
      context_done_valid_o <= 1'b0;
      context_done_o <= '0;
      for (int ctx = 0; ctx < GROUP_ROWS; ctx++) begin
        m_q[ctx] <= '0;
        l_q[ctx] <= '0;
        for (int lane = 0; lane < D; lane++) begin
          acc_q[ctx][lane] <= '0;
        end
      end
      for (int stage = 0; stage <= SCORE_PIPE_LATENCY; stage++) begin
        score_context_pipe_q[stage] <= '0;
        score_last_pipe_q[stage] <= 1'b0;
        for (int lane = 0; lane < D; lane++) begin
          score_v_pipe_q[stage][lane] <= '0;
        end
      end
      for (int lane = 0; lane < D; lane++) begin
        update_v_q[lane] <= '0;
      end
      for (int stage = 0; stage < FINAL_CONTEXT_LATENCY; stage++) begin
        final_context_pipe[stage] <= '0;
      end
    end else begin
      context_done_valid_o <= 1'b0;

      if (init_valid_i && init_ready_o) begin
        seen_q[init_context_i] <= 1'b0;
        m_q[init_context_i] <= '0;
        l_q[init_context_i] <= '0;
        for (int lane = 0; lane < D; lane++) begin
          acc_q[init_context_i][lane] <= '0;
        end
      end

      score_context_pipe_q[0] <= score_accept ? score_context_i : '0;
      score_last_pipe_q[0] <= score_accept ? score_last_i : 1'b0;
      for (int lane = 0; lane < D; lane++) begin
        score_v_pipe_q[0][lane] <= score_accept ? v_i[lane] : '0;
      end
      for (int stage = 1; stage <= SCORE_PIPE_LATENCY; stage++) begin
        score_context_pipe_q[stage] <= score_context_pipe_q[stage-1];
        score_last_pipe_q[stage] <= score_last_pipe_q[stage-1];
        for (int lane = 0; lane < D; lane++) begin
          score_v_pipe_q[stage][lane] <= score_v_pipe_q[stage-1][lane];
        end
      end

      if (score_accept) begin
        pending_q[score_context_i] <= 1'b1;
      end

      if (score_pipe_valid) begin
        update_context_q <= score_context_pipe_q[SCORE_PIPE_LATENCY];
        update_last_q <= score_last_pipe_q[SCORE_PIPE_LATENCY];
        update_op_q <= issue_op;
        update_new_m_q <= issue_new_m;
        for (int lane = 0; lane < D; lane++) begin
          update_v_q[lane] <= score_v_pipe_q[SCORE_PIPE_LATENCY][lane];
        end
      end

      if (exp_valid) begin
        seen_q[update_context_q] <= 1'b1;
        pending_q[update_context_q] <= 1'b0;
        m_q[update_context_q] <= update_new_m_q;
        l_q[update_context_q] <= commit_l_next;
        for (int lane = 0; lane < D; lane++) begin
          acc_q[update_context_q][lane] <= commit_acc_next[lane];
        end
        context_done_valid_o <= 1'b1;
        context_done_o <= update_context_q;
      end

      final_context_pipe[0] <= finalize_valid_i ? update_context_q : '0;
      for (int stage = 1; stage < FINAL_CONTEXT_LATENCY; stage++) begin
        final_context_pipe[stage] <= final_context_pipe[stage-1];
      end
    end
  end
endmodule
