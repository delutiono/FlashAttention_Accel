`timescale 1ns/1ps

module tb_finalize_vec;
  localparam int unsigned D = 64;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam int unsigned OUT_W = 16;
  localparam logic [L_W-1:0] L_ONE = {{(L_W-24){1'b0}}, 24'h800000};
  localparam logic [L_W-1:0] L_TWO = {{(L_W-25){1'b0}}, 25'h1000000};
  localparam logic [L_W-1:0] L_ONE_PLUS_EXP_NEG_ONE = 32'h00af_16ac;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic [L_W-1:0] l_i;
  logic signed [ACC_W-1:0] acc_i [D];
  logic valid_o;
  logic signed [OUT_W-1:0] o_q88_o [D];

  fa_finalize_vec #(
    .D(D),
    .L_W(L_W),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .l_i,
    .acc_i,
    .valid_o,
    .o_q88_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic signed [ACC_W-1:0] acc_from_q88(
    input logic signed [OUT_W-1:0] q88
  );
    logic signed [ACC_W-1:0] widened;
    begin
      widened = {{(ACC_W-OUT_W){q88[OUT_W-1]}}, q88};
      return widened <<< 23;
    end
  endfunction

  task automatic clear_inputs;
    int lane;
    begin
      valid_i = 1'b0;
      l_i = '0;
      for (lane = 0; lane < D; lane++) begin
        acc_i[lane] = '0;
      end
    end
  endtask

  task automatic check_lane(
    input string name,
    input int lane,
    input logic signed [OUT_W-1:0] expected
  );
    begin
      if (o_q88_o[lane] !== expected) begin
        $fatal(1, "%s lane%0d o_q88_o=0x%04h expected=0x%04h",
               name, lane, o_q88_o[lane], expected);
      end
    end
  endtask

  task automatic wait_finalize_output;
    begin
      @(posedge clk);
      @(negedge clk);
      clear_inputs();
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    int lane;

    rst_n = 1'b0;
    clear_inputs();

    #1;
    if (valid_o !== 1'b0) begin
      $fatal(1, "reset valid_o not clear");
    end
    for (lane = 0; lane < D; lane++) begin
      check_lane("reset", lane, '0);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    @(negedge clk);
    valid_i = 1'b1;
    l_i = L_ONE;
    for (lane = 0; lane < D; lane++) begin
      acc_i[lane] = acc_from_q88(16'sh0000);
    end
    acc_i[0] = acc_from_q88(16'sh0100);
    acc_i[1] = acc_from_q88(16'shff00);
    acc_i[2] = acc_from_q88(16'sh0080);
    acc_i[63] = acc_from_q88(16'sh0000);
    wait_finalize_output();

    if (valid_o !== 1'b1) begin
      $fatal(1, "causal_i0 valid_o=%0b expected=1", valid_o);
    end
    check_lane("causal_i0", 0, 16'sh0100);
    check_lane("causal_i0", 1, 16'shff00);
    check_lane("causal_i0", 2, 16'sh0080);
    check_lane("causal_i0", 63, 16'sh0000);

    @(negedge clk);
    valid_i = 1'b1;
    l_i = L_TWO;
    for (lane = 0; lane < D; lane++) begin
      acc_i[lane] = '0;
    end
    acc_i[0] = acc_from_q88(16'sh0180);
    acc_i[1] = acc_from_q88(16'sh0000);
    acc_i[2] = acc_from_q88(16'sh0001);
    acc_i[3] = acc_from_q88(16'shffff);
    wait_finalize_output();

    if (valid_o !== 1'b1) begin
      $fatal(1, "l2 valid_o=%0b expected=1", valid_o);
    end
    check_lane("l2", 0, 16'sh00c0);
    check_lane("l2", 1, 16'sh0000);
    check_lane("l2", 2, 16'sh0001);
    check_lane("l2", 3, 16'shffff);

    @(negedge clk);
    valid_i = 1'b1;
    l_i = L_ONE_PLUS_EXP_NEG_ONE;
    for (lane = 0; lane < D; lane++) begin
      acc_i[lane] = '0;
    end
    acc_i[0] = acc_from_q88(16'sh0100);
    wait_finalize_output();

    if (valid_o !== 1'b1) begin
      $fatal(1, "l_1_plus_exp_neg_one valid_o=%0b expected=1", valid_o);
    end
    // recip_l uses the quantized l value 0x00af16ac: round((2^31*2^23)/l) = 0x5d935411.
    check_lane("l_1_plus_exp_neg_one", 0, 16'sh00bb);

    @(negedge clk);
    valid_i = 1'b1;
    l_i = L_ONE;
    for (lane = 0; lane < D; lane++) begin
      acc_i[lane] = '0;
    end
    acc_i[0] = acc_from_q88(16'sh7fff) + (48'sd1 <<< 23);
    acc_i[1] = acc_from_q88(16'sh8000) - (48'sd1 <<< 23);
    wait_finalize_output();

    if (valid_o !== 1'b1) begin
      $fatal(1, "saturation valid_o=%0b expected=1", valid_o);
    end
    check_lane("saturation", 0, 16'sh7fff);
    check_lane("saturation", 1, 16'sh8000);

    @(negedge clk);
    valid_i = 1'b1;
    l_i = L_ONE + 32'd1;
    for (lane = 0; lane < D; lane++) begin
      acc_i[lane] = acc_from_q88(16'sh0123);
    end
    wait_finalize_output();

    if (valid_o !== 1'b0) begin
      $fatal(1, "unsupported l_i valid_o=%0b expected=0", valid_o);
    end

    $display("tb_finalize_vec PASS");
    $finish;
  end
endmodule
