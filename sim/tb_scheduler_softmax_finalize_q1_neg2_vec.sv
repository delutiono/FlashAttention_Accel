`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_softmax_finalize_q1_neg2_vec;
  localparam int unsigned S = 256;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned SCORE_PIPE_W = 48;
  localparam int unsigned SOFTMAX_SCORE_W = 24;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam int unsigned OUT_W = 16;

  localparam logic [L_W-1:0] L_ONE = 32'h0080_0000;
  localparam logic [L_W-1:0] L_ONE_PLUS_EXP_NEG_TWO = 32'h0091_52ab;
  localparam logic [31:0] RECIP_ONE_PLUS_EXP_NEG_TWO = 32'h70bd_f523;
  localparam logic signed [SCORE_PIPE_W-1:0] SCORE_NEG_TWO_48 = -48'sd131072;
  localparam logic signed [SOFTMAX_SCORE_W-1:0] SOFTMAX_SCORE_NEG_TWO =
      -24'sd131072;

  logic clk;
  logic rst_n;
  logic start_i;
  logic row_start_i;
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
  logic signed [SCORE_PIPE_W-1:0] score;
  logic signed [SOFTMAX_SCORE_W-1:0] softmax_score;
  logic signed [ELEM_W-1:0] v_vec [D];

  logic softmax_valid;
  logic signed [SOFTMAX_SCORE_W-1:0] softmax_m;
  logic [L_W-1:0] softmax_l;
  logic signed [ACC_W-1:0] softmax_acc [D];
  logic softmax_tag_valid;
  logic softmax_tag_hold;
  logic [7:0] softmax_q_index;
  logic [7:0] softmax_k_index;

  logic finalize_valid;
  logic [L_W-1:0] finalize_l;
  logic signed [ACC_W-1:0] finalize_acc [D];
  logic finalize_valid_o;
  logic signed [OUT_W-1:0] finalize_o_q88 [D];

  logic [ELEM_W-1:0] q_mem [S * D];
  logic [ELEM_W-1:0] k_mem [S * D];
  logic [ELEM_W-1:0] v_mem [S * D];

  int unsigned q1_score_count;
  int unsigned q1_softmax_count;
  int unsigned q1_finalize_count;
  bit saw_q1_row_start;
  bit saw_q1_k2_masked;
  bit saw_q1_masked_hold;
  bit q1_done;
  logic signed [SOFTMAX_SCORE_W-1:0] q1_hold_m;
  logic [L_W-1:0] q1_hold_l;
  logic signed [ACC_W-1:0] q1_hold_acc00;
  logic signed [ACC_W-1:0] q1_hold_acc01;
  logic signed [ACC_W-1:0] q1_hold_acc63;
  logic [31:0] observed_q1_recip;
  logic signed [OUT_W-1:0] observed_q1_o00;
  logic signed [OUT_W-1:0] observed_q1_o01;
  logic signed [OUT_W-1:0] observed_q1_o63;

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
    .SCORE_W(SCORE_PIPE_W)
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

  fa_softmax_online_vec #(
    .D(D),
    .SCORE_W(SOFTMAX_SCORE_W),
    .L_W(L_W),
    .ACC_W(ACC_W)
  ) dut_softmax (
    .clk,
    .rst_n,
    .valid_i(score_valid),
    .row_start_i(row_start_i),
    .score_valid_i(score_valid),
    .score_i(softmax_score),
    .v_i(v_vec),
    .valid_o(softmax_valid),
    .m_o(softmax_m),
    .l_o(softmax_l),
    .acc_o(softmax_acc)
  );

  fa_finalize_vec #(
    .D(D),
    .L_W(L_W),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) dut_finalize (
    .clk,
    .rst_n,
    .valid_i(finalize_valid),
    .l_i(finalize_l),
    .acc_i(finalize_acc),
    .valid_o(finalize_valid_o),
    .o_q88_o(finalize_o_q88)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  assign softmax_score = score[SOFTMAX_SCORE_W-1:0];
  assign finalize_valid = softmax_valid;
  assign finalize_l = softmax_l;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      softmax_tag_valid <= 1'b0;
      softmax_tag_hold <= 1'b0;
      softmax_q_index <= 8'h0;
      softmax_k_index <= 8'h0;
    end else if (row_start_i) begin
      softmax_tag_valid <= 1'b0;
      softmax_tag_hold <= 1'b0;
      softmax_q_index <= 8'h0;
      softmax_k_index <= 8'h0;
    end else if (score_valid) begin
      softmax_tag_valid <= 1'b1;
      softmax_tag_hold <= 1'b1;
      softmax_q_index <= score_q_index;
      softmax_k_index <= score_k_index;
    end else if (softmax_tag_hold) begin
      softmax_tag_valid <= 1'b1;
      softmax_tag_hold <= 1'b0;
    end else begin
      softmax_tag_valid <= 1'b0;
    end
  end

  always_comb begin
    for (int lane = 0; lane < D; lane++) begin
      q_vec[lane] = $signed(q_mem[q_index_o * D + lane]);
      k_vec[lane] = $signed(k_mem[k_index_o * D + lane]);
      v_vec[lane] = $signed(v_mem[score_k_index * D + lane]);
      finalize_acc[lane] = softmax_acc[lane];
    end
  end

  function automatic logic signed [ACC_W-1:0] acc_from_q88(
    input logic signed [ELEM_W-1:0] q88
  );
    logic signed [ACC_W-1:0] widened;
    begin
      widened = {{(ACC_W-ELEM_W){q88[ELEM_W-1]}}, q88};
      return widened <<< 23;
    end
  endfunction

  function automatic logic signed [SCORE_PIPE_W-1:0] ref_dot(
    input logic [7:0] q_idx,
    input logic [7:0] k_idx
  );
    logic signed [SCORE_PIPE_W-1:0] acc;
    logic signed [31:0] prod;
    begin
      acc = '0;
      for (int lane = 0; lane < D; lane++) begin
        prod = $signed(q_mem[q_idx * D + lane]) *
               $signed(k_mem[k_idx * D + lane]);
        acc += {{(SCORE_PIPE_W-32){prod[31]}}, prod};
      end
      return acc;
    end
  endfunction

  function automatic logic signed [SCORE_PIPE_W-1:0] ref_scaled_score(
    input logic [7:0] q_idx,
    input logic [7:0] k_idx
  );
    begin
      return ref_dot(q_idx, k_idx) >>> 3;
    end
  endfunction

  task automatic init_controlled_vectors;
    begin
      for (int idx = 0; idx < S * D; idx++) begin
        q_mem[idx] = '0;
        k_mem[idx] = '0;
        v_mem[idx] = '0;
      end

      q_mem[1 * D + 0] = 16'sh0100;
      k_mem[0 * D + 0] = 16'sh0000;
      k_mem[1 * D + 0] = 16'shf000;

      v_mem[0 * D + 0] = 16'sh0100;

      v_mem[1 * D + 0] = 16'sh0200;

      v_mem[2 * D + 0] = 16'sh7f00;
      v_mem[2 * D + 1] = 16'sh7f00;
      v_mem[2 * D + 63] = 16'sh7f00;
    end
  endtask

  task automatic check_softmax_lane(
    input string tag,
    input int unsigned lane,
    input logic signed [ACC_W-1:0] expected
  );
    begin
      if (softmax_acc[lane] !== expected) begin
        $fatal(1, "%s softmax lane%0d acc=0x%012h expected=0x%012h",
               tag, lane, softmax_acc[lane], expected);
      end
    end
  endtask

  task automatic check_softmax_meta(
    input string tag,
    input logic [7:0] expected_k,
    input logic [L_W-1:0] expected_l
  );
    begin
      if (softmax_tag_valid !== 1'b1 ||
          softmax_q_index !== 8'd1 || softmax_k_index !== expected_k) begin
        $fatal(1, "%s softmax accepted q=%0d k=%0d expected q=1 k=%0d",
               tag, softmax_q_index, softmax_k_index, expected_k);
      end

      if (softmax_m !== '0 || softmax_l !== expected_l) begin
        $fatal(1, "%s softmax m=%0d l=0x%08h expected m=0 l=0x%08h",
               tag, softmax_m, softmax_l, expected_l);
      end
    end
  endtask

  task automatic check_q1_first_update(input string tag);
    begin
      check_softmax_meta(tag, 8'd0, L_ONE);
      check_softmax_lane(tag, 0, acc_from_q88(16'sh0100));
      check_softmax_lane(tag, 1, '0);
      check_softmax_lane(tag, 63, '0);
    end
  endtask

  task automatic check_q1_second_update(input string tag);
    begin
      check_softmax_meta(tag, 8'd1, L_ONE_PLUS_EXP_NEG_TWO);
      check_softmax_lane(tag, 0, 48'sh0000_a2a5_5600);
      check_softmax_lane(tag, 1, 48'sh0000_0000_0000);
      check_softmax_lane(tag, 63, 48'sh0000_0000_0000);
    end
  endtask

  task automatic check_q1_hold_after_mask(input string tag);
    begin
      if (softmax_m !== q1_hold_m || softmax_l !== q1_hold_l ||
          softmax_acc[0] !== q1_hold_acc00 ||
          softmax_acc[1] !== q1_hold_acc01 ||
          softmax_acc[63] !== q1_hold_acc63) begin
        $fatal(1, "%s masked k=2 changed q1 softmax state", tag);
      end
    end
  endtask

  task automatic check_finalize_lane(
    input string tag,
    input int unsigned lane,
    input logic signed [OUT_W-1:0] expected
  );
    begin
      if (finalize_o_q88[lane] !== expected) begin
        $fatal(1, "%s finalize lane%0d o_q88=0x%04h expected=0x%04h",
               tag, lane, finalize_o_q88[lane], expected);
      end
    end
  endtask

  task automatic check_q1_finalize(input string tag);
    begin
      if (q1_finalize_count == 1) begin
        check_finalize_lane(tag, 0, 16'sh0100);
        check_finalize_lane(tag, 1, 16'sh0000);
        check_finalize_lane(tag, 63, 16'sh0000);
      end else if (q1_finalize_count == 2) begin
        if (observed_q1_recip !== RECIP_ONE_PLUS_EXP_NEG_TWO) begin
          $fatal(1, "%s observed recip_l=0x%08h expected=0x%08h",
                 tag, observed_q1_recip, RECIP_ONE_PLUS_EXP_NEG_TWO);
        end
        check_finalize_lane(tag, 0, 16'sh011f);
        check_finalize_lane(tag, 1, 16'sh0000);
        check_finalize_lane(tag, 63, 16'sh0000);
        observed_q1_o00 = finalize_o_q88[0];
        observed_q1_o01 = finalize_o_q88[1];
        observed_q1_o63 = finalize_o_q88[63];
      end else begin
        $fatal(1, "%s q=1 emitted extra finalize valid %0d",
               tag, q1_finalize_count);
      end
    end
  endtask

  initial begin
    init_controlled_vectors();

    rst_n = 1'b0;
    start_i = 1'b0;
    row_start_i = 1'b0;
    q1_score_count = 0;
    q1_softmax_count = 0;
    q1_finalize_count = 0;
    saw_q1_row_start = 1'b0;
    saw_q1_k2_masked = 1'b0;
    saw_q1_masked_hold = 1'b0;
    q1_done = 1'b0;
    q1_hold_m = '0;
    q1_hold_l = '0;
    q1_hold_acc00 = '0;
    q1_hold_acc01 = '0;
    q1_hold_acc63 = '0;
    observed_q1_recip = '0;
    observed_q1_o00 = '0;
    observed_q1_o01 = '0;
    observed_q1_o63 = '0;

    if (ref_dot(8'd1, 8'd1) !== -48'sd1048576 ||
        ref_scaled_score(8'd1, 8'd0) !== '0 ||
        ref_scaled_score(8'd1, 8'd1) !== SCORE_NEG_TWO_48 ||
        ref_scaled_score(8'd1, 8'd2) !== '0) begin
      $fatal(1, "controlled q1/k scores do not match 0/-2/0");
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    start_i = 1'b1;
    @(negedge clk);
    start_i = 1'b0;

    for (int guard = 0; guard < 5000; guard++) begin
      @(posedge clk);
      #1;

      row_start_i = 1'b0;
      if (!saw_q1_row_start && state_o == FA_ST_COMPUTE_TILE &&
          q_index_o == 8'd1 && k_index_o == 8'd0 && score_valid_o) begin
        row_start_i = 1'b1;
        saw_q1_row_start = 1'b1;
      end

      if (state_o == FA_ST_COMPUTE_TILE && q_index_o == 8'd1 &&
          k_index_o == 8'd2 && !score_valid_o) begin
        saw_q1_k2_masked = 1'b1;
      end

      if (score_valid && score_q_index == 8'd1) begin
        q1_score_count++;

        if (score_k_index > 8'd1) begin
          $fatal(1, "q=1 emitted masked k=%0d score=%0d",
                 score_k_index, score);
        end

        if (score_k_index == 8'd0 && score !== '0) begin
          $fatal(1, "q=1 k=0 score=%0d expected 0", score);
        end

        if (score_k_index == 8'd1 && score !== SCORE_NEG_TWO_48) begin
          $fatal(1, "q=1 k=1 score=0x%012h expected 0xfffffffe0000",
                 score);
        end

        if (score_k_index == 8'd1 &&
            softmax_score !== SOFTMAX_SCORE_NEG_TWO) begin
          $fatal(1, "q=1 k=1 softmax_score=0x%06h expected 0xfe0000",
                 softmax_score);
        end
      end

      if (softmax_valid && softmax_q_index == 8'd1) begin
        q1_softmax_count++;

        if (q1_softmax_count == 1) begin
          check_q1_first_update("q1_k0");
        end else if (q1_softmax_count == 2) begin
          check_q1_second_update("q1_k1_final_delta_neg2");
          q1_hold_m = softmax_m;
          q1_hold_l = softmax_l;
          q1_hold_acc00 = softmax_acc[0];
          q1_hold_acc01 = softmax_acc[1];
          q1_hold_acc63 = softmax_acc[63];
        end else begin
          $fatal(1, "q=1 emitted %0d softmax valids, expected exactly two",
                 q1_softmax_count);
        end
      end

      if (saw_q1_k2_masked && q1_softmax_count == 2 &&
          !saw_q1_masked_hold && !score_valid && !softmax_valid) begin
        check_q1_hold_after_mask("q1_k2_masked_hold");
        saw_q1_masked_hold = 1'b1;
      end

      if (dut_finalize.recip_valid && q1_softmax_count == 2) begin
        observed_q1_recip = dut_finalize.recip_l;
        if (observed_q1_recip !== RECIP_ONE_PLUS_EXP_NEG_TWO) begin
          $fatal(1, "q1 second recip_l=0x%08h expected=0x%08h",
                 observed_q1_recip, RECIP_ONE_PLUS_EXP_NEG_TWO);
        end
      end

      if (finalize_valid_o && q1_softmax_count > 0) begin
        q1_finalize_count++;
        check_q1_finalize("q1_finalize");
      end

      if (q_index_o > 8'd1 || done_o || error_o) begin
        q1_done = 1'b1;
      end

      if (q1_done && q1_finalize_count == 2) begin
        break;
      end
    end

    if (error_o) begin
      $fatal(1, "scheduler entered error state");
    end

    if (!saw_q1_row_start) begin
      $fatal(1, "did not issue q=1 row_start pulse");
    end

    if (!saw_q1_k2_masked) begin
      $fatal(1, "did not observe q=1 k=2 masked at scheduler output");
    end

    if (!saw_q1_masked_hold) begin
      $fatal(1, "masked q=1 k=2 changed softmax state or emitted valid");
    end

    if (q1_score_count != 2) begin
      $fatal(1, "q=1 emitted %0d scores, expected exactly two",
             q1_score_count);
    end

    if (q1_softmax_count != 2) begin
      $fatal(1, "q=1 softmax emitted %0d valids, expected exactly two",
             q1_softmax_count);
    end

    if (q1_finalize_count != 2) begin
      $fatal(1, "q=1 finalize emitted %0d valids, expected exactly two",
             q1_finalize_count);
    end

    $display("tb_scheduler_softmax_finalize_q1_neg2_vec PASS q1_scores=%0d l1=0x%08h l2=0x%08h recip=0x%08h o00=0x%04h o01=0x%04h o63=0x%04h",
             q1_score_count, L_ONE, L_ONE_PLUS_EXP_NEG_TWO,
             observed_q1_recip, observed_q1_o00,
             observed_q1_o01, observed_q1_o63);
    $finish;
  end
endmodule
