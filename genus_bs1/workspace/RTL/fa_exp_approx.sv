`timescale 1ns/1ps

module fa_exp_approx #(
  parameter int unsigned IN_W = 24,
  parameter int unsigned OUT_W = 24
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    valid_i,
  input  logic signed [IN_W-1:0]  x_i,
  output logic                    valid_o,
  output logic [OUT_W-1:0]        y_o
);
  localparam logic signed [IN_W-1:0] X_ZERO = '0;
  localparam logic signed [IN_W-1:0] X_NEG_SIXTEEN =
      -$signed(IN_W'(32'd1048576));
  localparam logic [OUT_W-1:0] Y_ONE = OUT_W'(24'h800000);

  logic [OUT_W-1:0] y_next;
  logic [IN_W-1:0] magnitude;
  logic [5:0] segment;
  logic [14:0] offset;
  logic [OUT_W-1:0] y_hi;
  logic [OUT_W-1:0] y_lo;
  logic [OUT_W-1:0] y_diff;
  logic [OUT_W+14:0] interp_product;
  logic [OUT_W+15:0] rounded_product;
  logic [OUT_W:0] interp_drop;

  function automatic logic [OUT_W-1:0] anchor_value(input logic [5:0] index);
    begin
      case (index)
         0: anchor_value = OUT_W'(24'h800000);
         1: anchor_value = OUT_W'(24'h4da2cc);
         2: anchor_value = OUT_W'(24'h2f16ac);
         3: anchor_value = OUT_W'(24'h1c8f87);
         4: anchor_value = OUT_W'(24'h1152ab);
         5: anchor_value = OUT_W'(24'h0a81c3);
         6: anchor_value = OUT_W'(24'h065f6c);
         7: anchor_value = OUT_W'(24'h03dd82);
         8: anchor_value = OUT_W'(24'h02582b);
         9: anchor_value = OUT_W'(24'h016c05);
        10: anchor_value = OUT_W'(24'h00dcca);
        11: anchor_value = OUT_W'(24'h0085ea);
        12: anchor_value = OUT_W'(24'h005139);
        13: anchor_value = OUT_W'(24'h003144);
        14: anchor_value = OUT_W'(24'h001de1);
        15: anchor_value = OUT_W'(24'h001220);
        16: anchor_value = OUT_W'(24'h000afe);
        17: anchor_value = OUT_W'(24'h0006ab);
        18: anchor_value = OUT_W'(24'h00040b);
        19: anchor_value = OUT_W'(24'h000274);
        20: anchor_value = OUT_W'(24'h00017d);
        21: anchor_value = OUT_W'(24'h0000e7);
        22: anchor_value = OUT_W'(24'h00008c);
        23: anchor_value = OUT_W'(24'h000055);
        24: anchor_value = OUT_W'(24'h000034);
        25: anchor_value = OUT_W'(24'h00001f);
        26: anchor_value = OUT_W'(24'h000013);
        27: anchor_value = OUT_W'(24'h00000c);
        28: anchor_value = OUT_W'(24'h000007);
        29: anchor_value = OUT_W'(24'h000004);
        30: anchor_value = OUT_W'(24'h000003);
        31: anchor_value = OUT_W'(24'h000002);
        32: anchor_value = OUT_W'(24'h000001);
        default: anchor_value = '0;
      endcase
    end
  endfunction

  always_comb begin
    magnitude = $unsigned(-x_i);
    segment = magnitude[20:15];
    offset = magnitude[14:0];
    y_hi = anchor_value(segment);
    y_lo = anchor_value(segment + 1'b1);
    y_diff = y_hi - y_lo;
    interp_product = y_diff * offset;
    rounded_product = interp_product + (OUT_W + 16)'(32'd16384);
    interp_drop = rounded_product >> 15;

    if (x_i >= X_ZERO) begin
      y_next = Y_ONE;
    end else if (x_i < X_NEG_SIXTEEN) begin
      y_next = '0;
    end else begin
      y_next = y_hi - OUT_W'(interp_drop);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      y_o     <= '0;
    end else begin
      valid_o <= valid_i;
      y_o     <= y_next;
    end
  end
endmodule
