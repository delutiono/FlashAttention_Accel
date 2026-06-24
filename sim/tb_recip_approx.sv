`timescale 1ns/1ps

module tb_recip_approx;
  localparam int unsigned IN_W = 32;
  localparam int unsigned OUT_W = 32;
  localparam logic [IN_W-1:0] X_ONE = 32'h0080_0000;
  localparam logic [IN_W-1:0] X_ONE_POINT_FIVE = 32'h00c0_0000;
  localparam logic [IN_W-1:0] X_TWO = 32'h0100_0000;
  localparam logic [OUT_W-1:0] RECIP_ONE = 32'h8000_0000;
  localparam logic [OUT_W-1:0] RECIP_ONE_POINT_FIVE_MIN = 32'h5400_0000;
  localparam logic [OUT_W-1:0] RECIP_ONE_POINT_FIVE_MAX = 32'h5680_0000;
  localparam logic [OUT_W-1:0] RECIP_TWO = 32'h4000_0000;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic [IN_W-1:0] x_i;
  logic valid_o;
  logic [OUT_W-1:0] y_o;

  fa_recip_approx #(
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
    input logic [IN_W-1:0] in_x,
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
        $fatal(1, "%s: y_o=0x%08h expected=0x%08h", name, y_o, exp_y);
      end
    end
  endtask

  task automatic drive_and_check_range(
    input string name,
    input logic [IN_W-1:0] in_x,
    input logic [OUT_W-1:0] min_y,
    input logic [OUT_W-1:0] max_y
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
      if (y_o < min_y || y_o > max_y) begin
        $fatal(1, "%s: y_o=0x%08h expected range [0x%08h,0x%08h]",
               name, y_o, min_y, max_y);
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    valid_i = 1'b0;
    x_i = '0;

    #1;
    if (valid_o !== 1'b0 || y_o !== '0) begin
      $fatal(1, "reset_asserted: valid_o=%0b y_o=0x%08h", valid_o, y_o);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    drive_and_check("recip_one", X_ONE, RECIP_ONE);
    drive_and_check_range("recip_one_point_five_generic",
                          X_ONE_POINT_FIVE,
                          RECIP_ONE_POINT_FIVE_MIN,
                          RECIP_ONE_POINT_FIVE_MAX);
    drive_and_check("recip_two", X_TWO, RECIP_TWO);

    @(negedge clk);
    valid_i = 1'b0;
    x_i = X_ONE;
    @(posedge clk);
    #1;
    if (valid_o !== 1'b0) begin
      $fatal(1, "idle: valid_o=%0b expected=0", valid_o);
    end

    $display("tb_recip_approx PASS");
    $finish;
  end
endmodule
