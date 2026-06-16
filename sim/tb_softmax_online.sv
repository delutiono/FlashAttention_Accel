`timescale 1ns/1ps

module tb_softmax_online;
  localparam int unsigned SCORE_W = 24;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam logic [L_W-1:0] L_ONE = {{(L_W-24){1'b0}}, 24'd1 << 23};
  localparam logic [L_W-1:0] P_EXP_NEG_ONE = {{(L_W-24){1'b0}}, 24'h2f16ac};

  logic clk;
  logic rst_n;
  logic valid_i;
  logic row_start_i;
  logic score_valid_i;
  logic signed [SCORE_W-1:0] score_i;
  logic signed [15:0] v_i;
  logic valid_o;
  logic signed [SCORE_W-1:0] m_o;
  logic [L_W-1:0] l_o;
  logic signed [ACC_W-1:0] acc_o;

  fa_softmax_online #(
    .SCORE_W(SCORE_W),
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
    .valid_o,
    .m_o,
    .l_o,
    .acc_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic signed [ACC_W-1:0] ref_acc(
    input logic signed [15:0] v
  );
    logic signed [ACC_W-1:0] widened;
    begin
      widened = {{(ACC_W-16){v[15]}}, v};
      return widened <<< 23;
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] ref_weighted_acc(
    input logic signed [15:0] v,
    input logic [23:0] p
  );
    logic signed [39:0] product;
    begin
      product = $signed(v) * $signed({1'b0, p});
      return {{(ACC_W-40){product[39]}}, product};
    end
  endfunction

  function automatic logic [L_W-1:0] ref_l_scaled(
    input logic [L_W-1:0] l,
    input logic [23:0] alpha
  );
    logic [L_W+24-1:0] product;
    begin
      product = l * alpha;
      return product[L_W+24-1:23];
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] ref_acc_scaled(
    input logic signed [ACC_W-1:0] acc,
    input logic [23:0] alpha
  );
    logic signed [ACC_W+25-1:0] product;
    begin
      product = acc * $signed({1'b0, alpha});
      return product[ACC_W+25-1:23];
    end
  endfunction

  task automatic check_outputs(
    input string name,
    input logic exp_valid,
    input logic signed [SCORE_W-1:0] exp_m,
    input logic [L_W-1:0] exp_l,
    input logic signed [ACC_W-1:0] exp_acc
  );
    begin
      if (valid_o !== exp_valid) begin
        $fatal(1, "%s: valid_o=%0b expected=%0b", name, valid_o, exp_valid);
      end
      if (m_o !== exp_m) begin
        $fatal(1, "%s: m_o=%0d expected=%0d", name, m_o, exp_m);
      end
      if (l_o !== exp_l) begin
        $fatal(1, "%s: l_o=0x%08h expected=0x%08h", name, l_o, exp_l);
      end
      if (acc_o !== exp_acc) begin
        $fatal(1, "%s: acc_o=%0d expected=%0d", name, acc_o, exp_acc);
      end
    end
  endtask

  task automatic drive_case(
    input string name,
    input logic in_valid,
    input logic in_row_start,
    input logic in_score_valid,
    input logic signed [SCORE_W-1:0] in_score,
    input logic signed [15:0] in_v,
    input logic exp_valid,
    input logic signed [SCORE_W-1:0] exp_m,
    input logic [L_W-1:0] exp_l,
    input logic signed [ACC_W-1:0] exp_acc
  );
    begin
      @(negedge clk);
      valid_i = in_valid;
      row_start_i = in_row_start;
      score_valid_i = in_score_valid;
      score_i = in_score;
      v_i = in_v;
      @(posedge clk);
      #1;
      check_outputs(name, exp_valid, exp_m, exp_l, exp_acc);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    valid_i = 1'b0;
    row_start_i = 1'b0;
    score_valid_i = 1'b0;
    score_i = '0;
    v_i = '0;

    #1;
    check_outputs("reset_asserted", 1'b0, '0, '0, '0);

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    drive_case("masked_first_holds_reset_state",
               1'b1, 1'b1, 1'b0, 24'sd12345, -16'sd256,
               1'b0, '0, '0, '0);

    drive_case("first_valid_positive_v",
               1'b1, 1'b0, 1'b1, 24'sd4096, 16'sd384,
               1'b1, 24'sd4096, L_ONE, ref_acc(16'sd384));

    drive_case("masked_score_after_valid_holds_state",
               1'b1, 1'b0, 1'b0, -24'sd2048, 16'sd512,
               1'b0, 24'sd4096, L_ONE, ref_acc(16'sd384));

    drive_case("second_equal_valid_accumulates",
               1'b1, 1'b0, 1'b1, 24'sd4096, -16'sd128,
               1'b1, 24'sd4096, L_ONE << 1,
               ref_acc(16'sd384) + ref_acc(-16'sd128));

    drive_case("third_lower_by_one_valid_accumulates_p",
               1'b1, 1'b0, 1'b1, 24'sd4096 - 24'sd65536, 16'sd256,
               1'b1, 24'sd4096, (L_ONE << 1) + P_EXP_NEG_ONE,
               ref_acc(16'sd384) + ref_acc(-16'sd128) +
               ref_weighted_acc(16'sd256, 24'h2f16ac));

    drive_case("row_start_resets_state",
               1'b0, 1'b1, 1'b0, 24'sd0, 16'sd0,
               1'b0, '0, '0, '0);

    drive_case("bringup_gt_first_valid_v1",
               1'b1, 1'b0, 1'b1, 24'sd0, 16'sd256,
               1'b1, 24'sd0, L_ONE, ref_acc(16'sd256));

    drive_case("bringup_gt_by_one_updates_m_and_renormalizes",
               1'b1, 1'b0, 1'b1, 24'sd65536, 16'sd512,
               1'b1, 24'sd65536, ref_l_scaled(L_ONE, 24'h2f16ac) + L_ONE,
               ref_acc_scaled(ref_acc(16'sd256), 24'h2f16ac) + ref_acc(16'sd512));

    drive_case("row_start_resets_after_bringup_gt",
               1'b0, 1'b1, 1'b0, 24'sd0, 16'sd0,
               1'b0, '0, '0, '0);

    drive_case("first_valid_negative_v",
               1'b1, 1'b0, 1'b1, -24'sd8192, -16'sd640,
               1'b1, -24'sd8192, L_ONE, ref_acc(-16'sd640));

    drive_case("idle_holds_outputs",
               1'b0, 1'b0, 1'b0, 24'sd777, 16'sd777,
               1'b0, -24'sd8192, L_ONE, ref_acc(-16'sd640));

    $display("tb_softmax_online PASS");
    $finish;
  end
endmodule
