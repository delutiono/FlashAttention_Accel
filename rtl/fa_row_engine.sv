`timescale 1ns/1ps

module fa_row_engine #(
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned SCORE_PIPE_W = 48,
  parameter int unsigned SOFTMAX_SCORE_W = 24,
  parameter int unsigned EXP_W = 24,
  parameter int unsigned L_W = 32,
  parameter int unsigned ACC_W = 48,
  parameter int unsigned OUT_W = 16
) (
  input  logic                              clk,
  input  logic                              rst_n,
  input  logic                              valid_i,
  input  logic                              row_start_i,
  input  logic                              last_i,
  input  logic [7:0]                        q_index_i,
  input  logic [7:0]                        k_index_i,
  input  var logic signed [ELEM_W-1:0]      q_i [D],
  input  var logic signed [ELEM_W-1:0]      k_i [D],
  input  var logic signed [ELEM_W-1:0]      v_i [D],
  output logic                              ready_o,
  output logic                              busy_o,
  output logic                              valid_o,
  output logic                              div_zero_o,
  output logic signed [OUT_W-1:0]           o_q88_o [D]
);
  localparam int unsigned SCORE_PIPE_LATENCY = 2;

  logic                              input_accept;
  logic                              drain_q;
  logic                              active_q;

  logic                              score_valid;
  logic signed [SCORE_PIPE_W-1:0]    score;
  logic signed [SOFTMAX_SCORE_W-1:0] softmax_score;

  logic                              score_row_start_pipe_q [0:SCORE_PIPE_LATENCY];
  logic                              score_last_pipe_q [0:SCORE_PIPE_LATENCY];
  logic signed [ELEM_W-1:0]          score_v_pipe_q [0:SCORE_PIPE_LATENCY][D];

  logic                              softmax_ready;
  logic                              softmax_valid;
  logic [L_W-1:0]                    softmax_l;
  logic signed [ACC_W-1:0]           softmax_acc [D];
  logic                              softmax_last_q;

  logic                              finalize_valid_i;

  assign ready_o = rst_n && softmax_ready && !drain_q;
  assign input_accept = valid_i && ready_o;
  assign softmax_score = score[SOFTMAX_SCORE_W-1:0];
  assign finalize_valid_i = softmax_valid && softmax_last_q;
  assign busy_o = active_q;

  fa_score_pipe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .SCORE_W(SCORE_PIPE_W)
  ) u_score_pipe (
    .clk,
    .rst_n,
    .valid_i(input_accept),
    .q_index_i,
    .k_index_i,
    .q_i,
    .k_i,
    .valid_o(score_valid),
    .q_index_o(),
    .k_index_o(),
    .score_o(score)
  );

  fa_softmax_online_vec #(
    .D(D),
    .SCORE_W(SOFTMAX_SCORE_W),
    .EXP_W(EXP_W),
    .L_W(L_W),
    .ACC_W(ACC_W)
  ) u_softmax (
    .clk,
    .rst_n,
    .valid_i(score_valid),
    .row_start_i(score_valid && score_row_start_pipe_q[SCORE_PIPE_LATENCY]),
    .score_valid_i(score_valid),
    .score_i(softmax_score),
    .v_i(score_v_pipe_q[SCORE_PIPE_LATENCY]),
    .ready_o(softmax_ready),
    .valid_o(softmax_valid),
    .m_o(),
    .l_o(softmax_l),
    .acc_o(softmax_acc)
  );

  fa_finalize_vec #(
    .D(D),
    .L_W(L_W),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) u_finalize (
    .clk,
    .rst_n,
    .valid_i(finalize_valid_i),
    .l_i(softmax_l),
    .acc_i(softmax_acc),
    .valid_o,
    .div_zero_o,
    .o_q88_o
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      softmax_last_q <= 1'b0;
      drain_q <= 1'b0;
      active_q <= 1'b0;
      for (int stage = 0; stage <= SCORE_PIPE_LATENCY; stage++) begin
        score_row_start_pipe_q[stage] <= 1'b0;
        score_last_pipe_q[stage] <= 1'b0;
        for (int lane = 0; lane < D; lane++) begin
          score_v_pipe_q[stage][lane] <= '0;
        end
      end
    end else begin
      score_row_start_pipe_q[0] <= input_accept ? row_start_i : 1'b0;
      score_last_pipe_q[0] <= input_accept ? last_i : 1'b0;
      for (int lane = 0; lane < D; lane++) begin
        score_v_pipe_q[0][lane] <= input_accept ? v_i[lane] : '0;
      end
      for (int stage = 1; stage <= SCORE_PIPE_LATENCY; stage++) begin
        score_row_start_pipe_q[stage] <= score_row_start_pipe_q[stage-1];
        score_last_pipe_q[stage] <= score_last_pipe_q[stage-1];
        for (int lane = 0; lane < D; lane++) begin
          score_v_pipe_q[stage][lane] <= score_v_pipe_q[stage-1][lane];
        end
      end

      if (score_valid && score_last_pipe_q[SCORE_PIPE_LATENCY]) begin
        softmax_last_q <= 1'b1;
      end else if (softmax_valid && softmax_last_q) begin
        softmax_last_q <= 1'b0;
      end

      if (input_accept) begin
        active_q <= 1'b1;
      end else if (valid_o) begin
        active_q <= 1'b0;
      end

      if (input_accept && last_i) begin
        drain_q <= 1'b1;
      end else if (valid_o) begin
        drain_q <= 1'b0;
      end
    end
  end
endmodule
