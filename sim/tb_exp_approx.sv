`timescale 1ns/1ps

module tb_exp_approx;
  localparam int unsigned IN_W = 24;
  localparam int unsigned OUT_W = 24;
  localparam int signed HALF_STEP = 32768;

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

  function automatic logic signed [IN_W-1:0] anchor_x(input int index);
    anchor_x = -$signed(index * HALF_STEP);
  endfunction

  function automatic logic [OUT_W-1:0] exp_anchor(input int index);
    begin
      case (index)
         0: exp_anchor = 24'h800000;
         1: exp_anchor = 24'h4da2cc;
         2: exp_anchor = 24'h2f16ac;
         3: exp_anchor = 24'h1c8f87;
         4: exp_anchor = 24'h1152ab;
         5: exp_anchor = 24'h0a81c3;
         6: exp_anchor = 24'h065f6c;
         7: exp_anchor = 24'h03dd82;
         8: exp_anchor = 24'h02582b;
         9: exp_anchor = 24'h016c05;
        10: exp_anchor = 24'h00dcca;
        11: exp_anchor = 24'h0085ea;
        12: exp_anchor = 24'h005139;
        13: exp_anchor = 24'h003144;
        14: exp_anchor = 24'h001de1;
        15: exp_anchor = 24'h001220;
        16: exp_anchor = 24'h000afe;
        17: exp_anchor = 24'h0006ab;
        18: exp_anchor = 24'h00040b;
        19: exp_anchor = 24'h000274;
        20: exp_anchor = 24'h00017d;
        21: exp_anchor = 24'h0000e7;
        22: exp_anchor = 24'h00008c;
        23: exp_anchor = 24'h000055;
        24: exp_anchor = 24'h000034;
        25: exp_anchor = 24'h00001f;
        26: exp_anchor = 24'h000013;
        27: exp_anchor = 24'h00000c;
        28: exp_anchor = 24'h000007;
        29: exp_anchor = 24'h000004;
        30: exp_anchor = 24'h000003;
        31: exp_anchor = 24'h000002;
        32: exp_anchor = 24'h000001;
        default: exp_anchor = 'x;
      endcase
    end
  endfunction

  function automatic logic [OUT_W-1:0] midpoint_y(input int index);
    logic [OUT_W-1:0] y_hi;
    logic [OUT_W-1:0] y_lo;
    logic [OUT_W:0] diff;
    begin
      y_hi = exp_anchor(index);
      y_lo = exp_anchor(index + 1);
      diff = y_hi - y_lo;
      midpoint_y = y_hi - ((diff + 1'b1) >> 1);
    end
  endfunction

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
        $fatal(1, "%s: x=%0d y_o=0x%06h expected=0x%06h",
               name, in_x, y_o, exp_y);
      end
    end
  endtask

  task automatic check_back_to_back;
    logic signed [IN_W-1:0] seq_x [0:7];
    logic [OUT_W-1:0] seq_y [0:7];
    int i;
    begin
      seq_x[0] = 24'sd1;
      seq_y[0] = 24'h800000;
      seq_x[1] = anchor_x(1);
      seq_y[1] = exp_anchor(1);
      seq_x[2] = anchor_x(3) - 24'sd16384;
      seq_y[2] = midpoint_y(3);
      seq_x[3] = anchor_x(16);
      seq_y[3] = exp_anchor(16);
      seq_x[4] = anchor_x(25) - 24'sd16384;
      seq_y[4] = midpoint_y(25);
      seq_x[5] = anchor_x(31);
      seq_y[5] = exp_anchor(31);
      seq_x[6] = anchor_x(32);
      seq_y[6] = exp_anchor(32);
      seq_x[7] = anchor_x(32) - 24'sd1;
      seq_y[7] = '0;

      for (i = 0; i < 8; i++) begin
        @(negedge clk);
        valid_i = 1'b1;
        x_i = seq_x[i];
        @(posedge clk);
        #1;
        if (valid_o !== 1'b1 || y_o !== seq_y[i]) begin
          $fatal(1,
                 "back_to_back[%0d]: x=%0d valid_o=%0b y_o=0x%06h expected=0x%06h",
                 i, seq_x[i], valid_o, y_o, seq_y[i]);
        end
      end
    end
  endtask

  initial begin
    int i;

    rst_n = 1'b0;
    valid_i = 1'b0;
    x_i = '0;

    #1;
    if (valid_o !== 1'b0 || y_o !== '0) begin
      $fatal(1, "reset_asserted: valid_o=%0b y_o=0x%06h", valid_o, y_o);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    drive_and_check("positive_clamps_to_one", 24'sd32768, 24'h800000);
    drive_and_check("neg_eight_tail_risk", anchor_x(16), exp_anchor(16));

    for (i = 0; i < 32; i++) begin
      drive_and_check($sformatf("anchor_%0d", i),
                      anchor_x(i), exp_anchor(i));
    end

    for (i = 0; i < 32; i++) begin
      drive_and_check($sformatf("midpoint_%0d", i),
                      anchor_x(i) - 24'sd16384, midpoint_y(i));
    end

    drive_and_check("neg_sixteen_uses_final_anchor",
                    anchor_x(32), exp_anchor(32));
    drive_and_check("below_neg_sixteen_clamps_to_zero",
                    anchor_x(32) - 24'sd1, '0);

    check_back_to_back();

    @(negedge clk);
    valid_i = 1'b0;
    x_i = '0;
    @(posedge clk);
    #1;
    if (valid_o !== 1'b0) begin
      $fatal(1, "idle: valid_o=%0b expected=0", valid_o);
    end

    $display("tb_exp_approx PASS");
    $finish;
  end
endmodule
