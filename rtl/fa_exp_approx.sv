`timescale 1ns/1ps

module fa_exp_approx #(
  parameter IN_W  = 16,
  parameter OUT_W = 16,
  parameter LUT_DEPTH = 4096,
  parameter LUT_ADDR_W = 12,
  parameter signed X_MIN_Q88 = -4096
) (
  input  logic                     clk,
  input  logic                     rst_n,
  input  logic                     valid_i,
  input  logic signed [IN_W-1:0]   x_i,
  output logic                     valid_o,
  output logic        [OUT_W-1:0]  y_o
);

  logic [OUT_W-1:0] exp_lut [0:LUT_DEPTH-1];

  initial begin
    $readmemh("rtl/exp_lut.hex", exp_lut);
  end

  logic signed [IN_W-1:0] x_clamped;
  logic [LUT_ADDR_W-1:0]  lut_addr;

  always_comb begin
    if (x_i > 0)
      x_clamped = 0;
    else if (x_i < X_MIN_Q88)
      x_clamped = X_MIN_Q88;
    else
      x_clamped = x_i;
  end

  assign lut_addr = (x_clamped == 0) ? LUT_ADDR_W'(LUT_DEPTH - 1) : LUT_ADDR_W'(x_clamped - X_MIN_Q88);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      y_o     <= '0;
    end else begin
      valid_o <= valid_i;
      if (valid_i)
        y_o <= exp_lut[lut_addr];
    end
  end

endmodule
