`timescale 1ns/1ps

module fa_out_quant #(
  parameter int unsigned IN_W = 48,
  parameter int unsigned RECIP_W = 32,
  parameter int unsigned OUT_W = 16
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         valid_i,
  input  logic signed [IN_W-1:0]       x_i,
  input  logic [RECIP_W-1:0]           recip_l_i,
  output logic                         valid_o,
  output logic signed [OUT_W-1:0]      y_o
);
  localparam int unsigned PRODUCT_W = IN_W + RECIP_W + 1;
  localparam int unsigned Q88_SHIFT = 54;
  localparam logic [PRODUCT_W-1:0] ROUND_HALF =
      ({{(PRODUCT_W-1){1'b0}}, 1'b1} << (Q88_SHIFT - 1));
  localparam logic [PRODUCT_W-1:0] OUT_POS_MAX =
      PRODUCT_W'(32'd32767);
  localparam logic [PRODUCT_W-1:0] OUT_NEG_ABS_MAX =
      PRODUCT_W'(32'd32768);

  logic signed [PRODUCT_W-1:0] product_next;

  assign product_next = $signed(x_i) * $signed({1'b0, recip_l_i});

  function automatic logic signed [OUT_W-1:0] quantize_q88(
    input logic signed [PRODUCT_W-1:0] product
  );
    logic negative;
    logic [PRODUCT_W-1:0] abs_product;
    logic [PRODUCT_W-1:0] rounded_abs;
    begin
      negative = product[PRODUCT_W-1];
      abs_product = negative ? $unsigned(-product) : $unsigned(product);
      rounded_abs = (abs_product + ROUND_HALF) >> Q88_SHIFT;

      if (!negative && (rounded_abs > OUT_POS_MAX)) begin
        return 16'sh7fff;
      end else if (negative && (rounded_abs >= OUT_NEG_ABS_MAX)) begin
        return 16'sh8000;
      end else if (negative) begin
        return -$signed(OUT_W'(rounded_abs));
      end else begin
        return $signed(OUT_W'(rounded_abs));
      end
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      y_o     <= '0;
    end else begin
      valid_o <= valid_i;
      y_o     <= valid_i ? quantize_q88(product_next) : '0;
    end
  end
endmodule
