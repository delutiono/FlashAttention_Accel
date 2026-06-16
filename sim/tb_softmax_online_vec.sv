`timescale 1ns/1ps

module tb_softmax_online_vec;
  localparam int unsigned D = 64;
  localparam int unsigned SCORE_W = 24;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam logic [L_W-1:0] L_ONE = {{(L_W-24){1'b0}}, 24'd1 << 23};
  localparam logic [23:0] EXP_NEG_HALF = 24'h4da2cc;
  localparam logic [23:0] EXP_NEG_ONE = 24'h2f16ac;
  localparam logic [23:0] EXP_NEG_TWO = 24'h1152ab;
  localparam logic [23:0] EXP_NEG_FOUR = 24'h02582b;
  localparam logic [L_W-1:0] L_EXP_NEG_HALF = {{(L_W-24){1'b0}}, EXP_NEG_HALF};
  localparam logic [L_W-1:0] L_EXP_NEG_ONE = {{(L_W-24){1'b0}}, EXP_NEG_ONE};
  localparam logic [L_W-1:0] L_EXP_NEG_TWO = {{(L_W-24){1'b0}}, EXP_NEG_TWO};
  localparam logic [L_W-1:0] L_EXP_NEG_FOUR = {{(L_W-24){1'b0}}, EXP_NEG_FOUR};

  logic clk;
  logic rst_n;
  logic valid_i;
  logic row_start_i;
  logic score_valid_i;
  logic signed [SCORE_W-1:0] score_i;
  logic signed [15:0] v_i [D];
  logic valid_o;
  logic signed [SCORE_W-1:0] m_o;
  logic [L_W-1:0] l_o;
  logic signed [ACC_W-1:0] acc_o [D];

  fa_softmax_online_vec #(
    .D(D),
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
    logic signed [ACC_W-1:0] widened;
    begin
      widened = {{(ACC_W-16){v[15]}}, v};
      return widened * $signed({1'b0, p});
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] ref_scaled_acc(
    input logic signed [ACC_W-1:0] acc,
    input logic [23:0] p
  );
    logic signed [ACC_W+25-1:0] product;
    begin
      product = acc * $signed({1'b0, p});
      return product[ACC_W+25-1:23];
    end
  endfunction

  task automatic clear_inputs;
    int lane;
    begin
      valid_i = 1'b0;
      row_start_i = 1'b0;
      score_valid_i = 1'b0;
      score_i = '0;
      for (lane = 0; lane < D; lane++) begin
        v_i[lane] = '0;
      end
    end
  endtask

  task automatic drive_valid(
    input logic signed [SCORE_W-1:0] in_score,
    input logic signed [15:0] base_v,
    input logic signed [15:0] lane0_v,
    input logic signed [15:0] lane1_v,
    input logic signed [15:0] lane63_v
  );
    int lane;
    begin
      @(negedge clk);
      valid_i = 1'b1;
      row_start_i = 1'b0;
      score_valid_i = 1'b1;
      score_i = in_score;
      for (lane = 0; lane < D; lane++) begin
        v_i[lane] = base_v + lane[15:0];
      end
      v_i[0] = lane0_v;
      v_i[1] = lane1_v;
      v_i[63] = lane63_v;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic pulse_row_start;
    begin
      @(negedge clk);
      valid_i = 1'b0;
      row_start_i = 1'b1;
      score_valid_i = 1'b0;
      @(posedge clk);
      #1;
      @(negedge clk);
      row_start_i = 1'b0;
    end
  endtask

  task automatic check_lane(
    input string name,
    input int lane,
    input logic signed [ACC_W-1:0] exp_acc
  );
    begin
      if (acc_o[lane] !== exp_acc) begin
        $fatal(1, "%s lane%0d acc_o=%0d expected=%0d",
               name, lane, acc_o[lane], exp_acc);
      end
    end
  endtask

  initial begin
    logic signed [15:0] first_v [D];
    logic signed [15:0] second_v [D];
    int lane;

    rst_n = 1'b0;
    clear_inputs();

    #1;
    if (valid_o !== 1'b0 || m_o !== '0 || l_o !== '0) begin
      $fatal(1, "reset outputs not clear");
    end
    for (lane = 0; lane < D; lane++) begin
      check_lane("reset", lane, '0);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    for (lane = 0; lane < D; lane++) begin
      first_v[lane] = 16'sd16 + lane[15:0];
      second_v[lane] = -16'sd8 + lane[15:0];
    end
    first_v[0] = 16'sh0100;
    first_v[1] = -16'sh0100;
    first_v[63] = 16'sh0200;
    second_v[0] = -16'sh0080;
    second_v[1] = 16'sh0040;
    second_v[63] = -16'sh0180;

    drive_valid(24'sd4096, 16'sd16, first_v[0], first_v[1], first_v[63]);

    if (valid_o !== 1'b1 || m_o !== 24'sd4096 || l_o !== L_ONE) begin
      $fatal(1, "first_valid metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end
    for (lane = 0; lane < D; lane++) begin
      check_lane("first_valid", lane, ref_acc(first_v[lane]));
    end

    drive_valid(24'sd4096, -16'sd8, second_v[0], second_v[1], second_v[63]);

    if (valid_o !== 1'b1 || m_o !== 24'sd4096 || l_o !== (L_ONE << 1)) begin
      $fatal(1, "equal_score metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end
    for (lane = 0; lane < D; lane++) begin
      check_lane("equal_score", lane, ref_acc(first_v[lane]) + ref_acc(second_v[lane]));
    end

    pulse_row_start();

    drive_valid(24'sd0, 16'sd0, 16'sh0100, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd0 || l_o !== L_ONE) begin
      $fatal(1, "lower_by_one_first metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end
    check_lane("lower_by_one_first", 0, ref_acc(16'sh0100));

    drive_valid(-24'sd65536, 16'sd0, 16'sh0200, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd0 || l_o !== (L_ONE + L_EXP_NEG_ONE)) begin
      $fatal(1, "lower_by_one metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end
    check_lane("lower_by_one", 0, ref_acc(16'sh0100) + ref_weighted_acc(16'sh0200, EXP_NEG_ONE));

    pulse_row_start();

    drive_valid(24'sd0, 16'sd0, 16'sh0100, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd0 || l_o !== L_ONE) begin
      $fatal(1, "higher_by_one_first metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end
    check_lane("higher_by_one_first", 0, ref_acc(16'sh0100));

    drive_valid(24'sd65536, 16'sd0, 16'sh0200, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd65536 || l_o !== (L_EXP_NEG_ONE + L_ONE)) begin
      $fatal(1, "higher_by_one metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end
    check_lane("higher_by_one", 0, ref_scaled_acc(ref_acc(16'sh0100), EXP_NEG_ONE) + ref_acc(16'sh0200));

    pulse_row_start();

    drive_valid(24'sd0, 16'sd0, 16'sh0100, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd0 || l_o !== L_ONE) begin
      $fatal(1, "exp_lower_first metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end
    check_lane("exp_lower_first", 0, 48'sh0000_8000_0000);

    drive_valid(-24'sd32768, 16'sd0, 16'sh0200, 16'sd0, 16'sd0);

    if (valid_o !== 1'b0 || m_o !== 24'sd0 || l_o !== L_ONE) begin
      $fatal(1, "exp_lower_neg_half_issue metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end

    clear_inputs();
    @(posedge clk);
    #1;

    if (valid_o !== 1'b1 || m_o !== 24'sd0 || l_o !== (L_ONE + L_EXP_NEG_HALF)) begin
      $fatal(1, "exp_lower_neg_half metadata valid=%0b m=%0d l=0x%08h expected_l=0x%08h p=0x%06h",
             valid_o, m_o, l_o, (L_ONE + L_EXP_NEG_HALF), EXP_NEG_HALF);
    end
    check_lane("exp_lower_neg_half", 0, 48'h0001_1b45_9800);

    pulse_row_start();

    drive_valid(24'sd0, 16'sd0, 16'sh0100, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd0 || l_o !== L_ONE) begin
      $fatal(1, "consecutive_exp_lower_first metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end

    drive_valid(-24'sd32768, 16'sd0, 16'sh0200, 16'sd0, 16'sd0);

    if (valid_o !== 1'b0 || m_o !== 24'sd0 || l_o !== L_ONE) begin
      $fatal(1, "consecutive_exp_lower_neg_half_issue metadata valid=%0b m=%0d l=0x%08h",
             valid_o, m_o, l_o);
    end

    drive_valid(-24'sd131072, 16'sd0, 16'shff00, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd0 ||
        l_o !== (L_ONE + L_EXP_NEG_HALF)) begin
      $fatal(1, "consecutive_exp_lower_neg_half metadata valid=%0b m=%0d l=0x%08h expected_l=0x%08h",
             valid_o, m_o, l_o, (L_ONE + L_EXP_NEG_HALF));
    end

    drive_valid(-24'sd262144, 16'sd0, 16'sh0080, 16'sd0, 16'sd0);

    if (valid_o !== 1'b1 || m_o !== 24'sd0 ||
        l_o !== (L_ONE + L_EXP_NEG_HALF + L_EXP_NEG_TWO)) begin
      $fatal(1, "consecutive_exp_lower_neg_two metadata valid=%0b m=%0d l=0x%08h expected_l=0x%08h",
             valid_o, m_o, l_o, (L_ONE + L_EXP_NEG_HALF + L_EXP_NEG_TWO));
    end

    clear_inputs();
    @(posedge clk);
    #1;

    if (valid_o !== 1'b1 || m_o !== 24'sd0 ||
        l_o !== (L_ONE + L_EXP_NEG_HALF + L_EXP_NEG_TWO + L_EXP_NEG_FOUR)) begin
      $fatal(1, "consecutive_exp_lower_neg_four metadata valid=%0b m=%0d l=0x%08h expected_l=0x%08h",
             valid_o, m_o, l_o,
             (L_ONE + L_EXP_NEG_HALF + L_EXP_NEG_TWO + L_EXP_NEG_FOUR));
    end

    $display("tb_softmax_online_vec PASS");
    $finish;
  end
endmodule
