`timescale 1ns/1ps

module tb_exp_approx;
  localparam int unsigned IN_W = 24;
  localparam int unsigned OUT_W = 24;
  localparam logic signed [IN_W-1:0] X_ZERO = '0;
  localparam logic signed [IN_W-1:0] X_NEG_HALF = -24'sd32768;
  localparam logic signed [IN_W-1:0] X_NEG_ONE = -24'sd65536;
  localparam logic signed [IN_W-1:0] X_NEG_TWO = -24'sd131072;
  localparam logic signed [IN_W-1:0] X_NEG_FOUR = -24'sd262144;
  localparam logic signed [IN_W-1:0] X_NEG_SIXTEEN = -24'sd1048576;
  localparam logic [OUT_W-1:0] EXP_ZERO = 24'h800000;
  localparam logic [OUT_W-1:0] EXP_NEG_HALF = 24'h4da2cc;
  localparam logic [OUT_W-1:0] EXP_NEG_ONE = 24'h2f16ac;
  localparam logic [OUT_W-1:0] EXP_NEG_TWO = 24'h1152ab;
  localparam logic [OUT_W-1:0] EXP_NEG_FOUR = 24'h02582b;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic signed [IN_W-1:0] x_i;
  logic valid_o;
  logic [OUT_W-1:0] y_o;

  fa_exp_approx #(
    .IN_W(IN_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .x_i,
    .valid_o,
    .y_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic drive_and_check(
    input string name,
    input logic signed [IN_W-1:0] in_x,
    input logic [OUT_W-1:0] exp_y
  );
    begin
      @(negedge clk);
      valid_i = 1'b1;
      x_i = in_x;
      @(posedge clk);
      #1;
      if (valid_o !== 1'b1) begin
        $fatal(1, "%s: valid_o=%0b expected=1", name, valid_o);
      end
      if (y_o !== exp_y) begin
        $fatal(1, "%s: y_o=0x%06h expected=0x%06h", name, y_o, exp_y);
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    valid_i = 1'b0;
    x_i = '0;

    #1;
    if (valid_o !== 1'b0 || y_o !== '0) begin
      $fatal(1, "reset_asserted: valid_o=%0b y_o=0x%06h", valid_o, y_o);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    drive_and_check("exp_zero", X_ZERO, EXP_ZERO);
    drive_and_check("exp_neg_half_s32_16", X_NEG_HALF, EXP_NEG_HALF);
    drive_and_check("exp_neg_one_s32_16", X_NEG_ONE, EXP_NEG_ONE);
    drive_and_check("exp_neg_two_s32_16", X_NEG_TWO, EXP_NEG_TWO);
    drive_and_check("exp_neg_four_s32_16", X_NEG_FOUR, EXP_NEG_FOUR);
    drive_and_check("unsupported_between_table_points", -24'sd98304, '0);
    drive_and_check("exp_neg_sixteen_underflows", X_NEG_SIXTEEN, '0);
    drive_and_check("exp_below_neg_sixteen_underflows", X_NEG_SIXTEEN - 24'sd1, '0);

    @(negedge clk);
    valid_i = 1'b0;
    x_i = X_ZERO;
    @(posedge clk);
    #1;
    if (valid_o !== 1'b0) begin
      $fatal(1, "idle: valid_o=%0b expected=0", valid_o);
    end

    $display("tb_exp_approx PASS");
    $finish;
  end
endmodule
