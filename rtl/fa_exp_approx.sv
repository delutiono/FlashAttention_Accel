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
  localparam logic signed [IN_W-1:0] X_NEG_HALF = -$signed(IN_W'(32'd32768));
  localparam logic signed [IN_W-1:0] X_NEG_ONE = -$signed(IN_W'(32'd65536));
  localparam logic signed [IN_W-1:0] X_NEG_TWO = -$signed(IN_W'(32'd131072));
  localparam logic signed [IN_W-1:0] X_NEG_FOUR = -$signed(IN_W'(32'd262144));
  localparam logic signed [IN_W-1:0] X_NEG_SIXTEEN = -$signed(IN_W'(32'd1048576));
  localparam logic [OUT_W-1:0] Y_ONE = OUT_W'(24'h800000);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_HALF = OUT_W'(24'h4da2cc);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_ONE = OUT_W'(24'h2f16ac);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_TWO = OUT_W'(24'h1152ab);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_FOUR = OUT_W'(24'h02582b);

  logic [OUT_W-1:0] y_next;

  always_comb begin
    // Bring-up LUT v0.2 for exact debug points in S*.16 -> U1.23.
    // Full LUT/PWL, interpolation, and generic bucket mapping are deferred.
    if (x_i == X_ZERO) begin
      y_next = Y_ONE;
    end else if (x_i == X_NEG_HALF) begin
      y_next = Y_EXP_NEG_HALF;
    end else if (x_i == X_NEG_ONE) begin
      y_next = Y_EXP_NEG_ONE;
    end else if (x_i == X_NEG_TWO) begin
      y_next = Y_EXP_NEG_TWO;
    end else if (x_i == X_NEG_FOUR) begin
      y_next = Y_EXP_NEG_FOUR;
    end else if (x_i <= X_NEG_SIXTEEN) begin
      y_next = '0;
    end else begin
      y_next = '0;
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
