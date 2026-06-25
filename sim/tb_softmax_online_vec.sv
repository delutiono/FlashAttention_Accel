`timescale 1ns/1ps

module tb_softmax_online_vec;
  localparam int unsigned D = 64;
  localparam int unsigned SCORE_W = 24;
  localparam int unsigned EXP_W = 24;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam logic [L_W-1:0] L_ONE = 32'h0080_0000;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic row_start_i;
  logic score_valid_i;
  logic signed [SCORE_W-1:0] score_i;
  logic signed [15:0] v_i [D];
  logic ready_o;
  logic valid_o;
  logic signed [SCORE_W-1:0] m_o;
  logic [L_W-1:0] l_o;
  logic signed [ACC_W-1:0] acc_o [D];

  logic model_seen;
  logic signed [SCORE_W-1:0] model_issue_m;
  logic signed [SCORE_W-1:0] model_commit_m;
  logic [L_W-1:0] model_l;
  logic signed [ACC_W-1:0] model_acc0;
  logic signed [ACC_W-1:0] model_acc1;
  logic signed [ACC_W-1:0] model_acc63;

  logic pending_expected;
  logic signed [SCORE_W-1:0] pending_m;
  logic [L_W-1:0] pending_l;
  logic signed [ACC_W-1:0] pending_acc0;
  logic signed [ACC_W-1:0] pending_acc1;
  logic signed [ACC_W-1:0] pending_acc63;

  fa_softmax_online_vec #(
    .D(D),
    .SCORE_W(SCORE_W),
    .EXP_W(EXP_W),
    .L_W(L_W),
    .ACC_W(ACC_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .row_start_i,
    .score_valid_i,
    .score_i,
    .v_i,
    .ready_o,
    .valid_o,
    .m_o,
    .l_o,
    .acc_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic [EXP_W-1:0] ref_exp(
    input logic signed [SCORE_W:0] x
  );
    int unsigned index;
    begin
      if (x >= 0) begin
        return 24'h800000;
      end
      if (x < -25'sd1048576) begin
        return '0;
      end

      index = $unsigned(-x) >> 15;
      case (index)
         0: ref_exp = 24'h800000;
         1: ref_exp = 24'h4da2cc;
         2: ref_exp = 24'h2f16ac;
         3: ref_exp = 24'h1c8f87;
         4: ref_exp = 24'h1152ab;
         5: ref_exp = 24'h0a81c3;
         6: ref_exp = 24'h065f6c;
         7: ref_exp = 24'h03dd82;
         8: ref_exp = 24'h02582b;
         9: ref_exp = 24'h016c05;
        10: ref_exp = 24'h00dcca;
        11: ref_exp = 24'h0085ea;
        12: ref_exp = 24'h005139;
        13: ref_exp = 24'h003144;
        14: ref_exp = 24'h001de1;
        15: ref_exp = 24'h001220;
        16: ref_exp = 24'h000afe;
        17: ref_exp = 24'h0006ab;
        18: ref_exp = 24'h00040b;
        19: ref_exp = 24'h000274;
        20: ref_exp = 24'h00017d;
        21: ref_exp = 24'h0000e7;
        22: ref_exp = 24'h00008c;
        23: ref_exp = 24'h000055;
        24: ref_exp = 24'h000034;
        25: ref_exp = 24'h00001f;
        26: ref_exp = 24'h000013;
        27: ref_exp = 24'h00000c;
        28: ref_exp = 24'h000007;
        29: ref_exp = 24'h000004;
        30: ref_exp = 24'h000003;
        31: ref_exp = 24'h000002;
        32: ref_exp = 24'h000001;
        default: ref_exp = '0;
      endcase
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] ref_v_scaled(
    input logic signed [15:0] value
  );
    logic signed [ACC_W-1:0] widened;
    begin
      widened = {{(ACC_W-16){value[15]}}, value};
      return widened <<< 23;
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] ref_v_weighted(
    input logic signed [15:0] value,
    input logic [EXP_W-1:0] factor
  );
    logic signed [ACC_W-1:0] widened;
    begin
      widened = {{(ACC_W-16){value[15]}}, value};
      return widened * $signed({1'b0, factor});
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] ref_acc_scaled(
    input logic signed [ACC_W-1:0] value,
    input logic [EXP_W-1:0] factor
  );
    logic signed [ACC_W+EXP_W:0] product;
    begin
      product = value * $signed({1'b0, factor});
      return product >>> 23;
    end
  endfunction

  function automatic logic [L_W-1:0] ref_l_scaled(
    input logic [L_W-1:0] value,
    input logic [EXP_W-1:0] factor
  );
    logic [L_W+EXP_W-1:0] product;
    begin
      product = value * factor;
      return product >> 23;
    end
  endfunction

  task automatic clear_inputs;
    begin
      valid_i = 1'b0;
      row_start_i = 1'b0;
      score_valid_i = 1'b0;
      score_i = '0;
      for (int lane = 0; lane < D; lane++) begin
        v_i[lane] = '0;
      end
    end
  endtask

  task automatic reset_model;
    begin
      model_seen = 1'b0;
      model_issue_m = '0;
      model_commit_m = '0;
      model_l = '0;
      model_acc0 = '0;
      model_acc1 = '0;
      model_acc63 = '0;
    end
  endtask

  task automatic check_commit(input string tag);
    begin
      if (valid_o !== pending_expected) begin
        $fatal(1, "%s valid_o=%0b expected=%0b",
               tag, valid_o, pending_expected);
      end
      if (pending_expected) begin
        if (m_o !== pending_m || l_o !== pending_l) begin
          $fatal(1,
                 "%s metadata m=%0d l=0x%08h expected_m=%0d expected_l=0x%08h",
                 tag, m_o, l_o, pending_m, pending_l);
        end
        if (acc_o[0] !== pending_acc0 ||
            acc_o[1] !== pending_acc1 ||
            acc_o[63] !== pending_acc63) begin
          $fatal(1,
                 "%s acc got={0x%012h,0x%012h,0x%012h} expected={0x%012h,0x%012h,0x%012h}",
                 tag, acc_o[0], acc_o[1], acc_o[63],
                 pending_acc0, pending_acc1, pending_acc63);
        end
      end
    end
  endtask

  task automatic model_accept(
    input logic signed [SCORE_W-1:0] in_score,
    input logic signed [15:0] value0,
    input logic signed [15:0] value1,
    input logic signed [15:0] value63
  );
    logic signed [SCORE_W:0] delta;
    logic [EXP_W-1:0] factor;
    begin
      if (!model_seen) begin
        model_seen = 1'b1;
        model_issue_m = in_score;
        model_commit_m = in_score;
        model_l = L_ONE;
        model_acc0 = ref_v_scaled(value0);
        model_acc1 = ref_v_scaled(value1);
        model_acc63 = ref_v_scaled(value63);
      end else if (in_score <= model_issue_m) begin
        delta = $signed({in_score[SCORE_W-1], in_score}) -
                $signed({model_issue_m[SCORE_W-1], model_issue_m});
        factor = ref_exp(delta);
        model_commit_m = model_issue_m;
        model_l = model_l + factor;
        model_acc0 = model_acc0 + ref_v_weighted(value0, factor);
        model_acc1 = model_acc1 + ref_v_weighted(value1, factor);
        model_acc63 = model_acc63 + ref_v_weighted(value63, factor);
      end else begin
        delta = $signed({model_issue_m[SCORE_W-1], model_issue_m}) -
                $signed({in_score[SCORE_W-1], in_score});
        factor = ref_exp(delta);
        model_issue_m = in_score;
        model_commit_m = in_score;
        model_l = ref_l_scaled(model_l, factor) + L_ONE;
        model_acc0 = ref_acc_scaled(model_acc0, factor) + ref_v_scaled(value0);
        model_acc1 = ref_acc_scaled(model_acc1, factor) + ref_v_scaled(value1);
        model_acc63 = ref_acc_scaled(model_acc63, factor) + ref_v_scaled(value63);
      end
    end
  endtask

  task automatic issue(
    input string tag,
    input logic signed [SCORE_W-1:0] in_score,
    input logic signed [15:0] value0,
    input logic signed [15:0] value1,
    input logic signed [15:0] value63
  );
    logic next_pending;
    logic signed [SCORE_W-1:0] next_m;
    logic [L_W-1:0] next_l;
    logic signed [ACC_W-1:0] next_acc0;
    logic signed [ACC_W-1:0] next_acc1;
    logic signed [ACC_W-1:0] next_acc63;
    begin
      @(negedge clk);
      clear_inputs();
      valid_i = 1'b1;
      score_valid_i = 1'b1;
      score_i = in_score;
      v_i[0] = value0;
      v_i[1] = value1;
      v_i[63] = value63;
      #1;
      if (ready_o !== 1'b1) begin
        $fatal(1, "%s ready_o=%0b expected=1", tag, ready_o);
      end

      model_accept(in_score, value0, value1, value63);
      next_pending = 1'b1;
      next_m = model_commit_m;
      next_l = model_l;
      next_acc0 = model_acc0;
      next_acc1 = model_acc1;
      next_acc63 = model_acc63;

      @(posedge clk);
      #1;
      check_commit({tag, "_previous"});
      pending_expected = next_pending;
      pending_m = next_m;
      pending_l = next_l;
      pending_acc0 = next_acc0;
      pending_acc1 = next_acc1;
      pending_acc63 = next_acc63;
    end
  endtask

  task automatic flush(input string tag);
    begin
      @(negedge clk);
      clear_inputs();
      #1;
      if (ready_o !== 1'b1) begin
        $fatal(1, "%s idle ready_o=%0b expected=1", tag, ready_o);
      end
      @(posedge clk);
      #1;
      check_commit(tag);
      pending_expected = 1'b0;
    end
  endtask

  task automatic start_row(input string tag);
    begin
      if (pending_expected) begin
        $fatal(1, "%s attempted clean row start with pending transaction", tag);
      end
      @(negedge clk);
      clear_inputs();
      row_start_i = 1'b1;
      #1;
      if (ready_o !== 1'b1) begin
        $fatal(1, "%s row_start ready_o=%0b expected=1", tag, ready_o);
      end
      @(posedge clk);
      #1;
      if (valid_o !== 1'b0 || m_o !== '0 || l_o !== '0) begin
        $fatal(1, "%s row clear failed valid=%0b m=%0d l=0x%08h",
               tag, valid_o, m_o, l_o);
      end
      reset_model();
      @(negedge clk);
      clear_inputs();
    end
  endtask

  task automatic test_row_start_while_pending;
    begin
      start_row("pending_row_setup");
      issue("pending_row_issue", 24'sd0, 16'sh0100, -16'sh0080, 16'sh0040);

      @(negedge clk);
      clear_inputs();
      row_start_i = 1'b1;
      #1;
      if (ready_o !== 1'b0) begin
        $fatal(1, "pending row_start ready_o=%0b expected=0", ready_o);
      end

      @(posedge clk);
      #1;
      check_commit("pending_row_commit");
      pending_expected = 1'b0;
      if (ready_o !== 1'b1) begin
        $fatal(1, "row_start did not become ready after pending commit");
      end

      @(posedge clk);
      #1;
      if (valid_o !== 1'b0 || m_o !== '0 || l_o !== '0 ||
          acc_o[0] !== '0 || acc_o[1] !== '0 || acc_o[63] !== '0) begin
        $fatal(1, "accepted row_start did not clear committed state");
      end
      reset_model();
      @(negedge clk);
      clear_inputs();
    end
  endtask

  initial begin
    rst_n = 1'b0;
    pending_expected = 1'b0;
    pending_m = '0;
    pending_l = '0;
    pending_acc0 = '0;
    pending_acc1 = '0;
    pending_acc63 = '0;
    clear_inputs();
    reset_model();

    #1;
    if (ready_o !== 1'b0 || valid_o !== 1'b0 ||
        m_o !== '0 || l_o !== '0) begin
      $fatal(1, "reset outputs ready=%0b valid=%0b m=%0d l=0x%08h",
             ready_o, valid_o, m_o, l_o);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    #1;
    if (ready_o !== 1'b1) begin
      $fatal(1, "ready_o not asserted after reset release");
    end

    start_row("positive_steps_setup");
    issue("positive_first", 24'sd0, 16'sh0100, -16'sh0080, 16'sh0040);
    issue("positive_half", 24'sd32768, 16'sh0200, 16'sh0100, -16'sh0080);
    issue("positive_one_half", 24'sd131072, 16'sh0300, -16'sh0180, 16'sh0100);
    issue("positive_two", 24'sd262144, 16'sh0400, 16'sh0200, -16'sh0100);
    flush("positive_two_commit");

    start_row("mixed_continuous_setup");
    issue("mixed_first", 24'sd0, 16'sh0100, 16'sh0080, -16'sh0040);
    issue("mixed_lower", -24'sd32768, 16'sh0200, -16'sh0100, 16'sh0080);
    issue("mixed_higher", 24'sd65536, 16'sh0300, 16'sh0180, -16'sh00c0);
    issue("mixed_equal", 24'sd65536, -16'sh0100, 16'sh0040, 16'sh0100);
    flush("mixed_equal_commit");

    start_row("wide_lower_setup");
    issue("wide_lower_first", 24'sh7f_ffff, 16'sh0100, 16'sh0080, 16'sh0040);
    issue("wide_lower_second", 24'sh80_0000, 16'sh0200, 16'sh0100, 16'sh0080);
    flush("wide_lower_commit");

    start_row("wide_higher_setup");
    issue("wide_higher_first", 24'sh80_0000, 16'sh0100, 16'sh0080, 16'sh0040);
    issue("wide_higher_second", 24'sh7f_ffff, 16'sh0200, 16'sh0100, 16'sh0080);
    flush("wide_higher_commit");

    start_row("neg_sixteen_setup");
    issue("neg_sixteen_first", 24'sd0, 16'sh0100, 16'sh0080, 16'sh0040);
    issue("neg_sixteen_exact", -24'sd1048576,
          16'sh0200, 16'sh0100, 16'sh0080);
    issue("neg_sixteen_below", -24'sd1048577,
          16'sh0400, 16'sh0200, 16'sh0100);
    flush("neg_sixteen_commit");

    test_row_start_while_pending();

    $display("tb_softmax_online_vec PASS");
    $finish;
  end
endmodule
