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
  localparam logic signed [IN_W-1:0] X_NEG_ONE_POINT_FIVE =
      -$signed(IN_W'(32'd98304));
  localparam logic signed [IN_W-1:0] X_NEG_TWO = -$signed(IN_W'(32'd131072));
  localparam logic signed [IN_W-1:0] X_NEG_TWO_POINT_FIVE =
      -$signed(IN_W'(32'd163840));
  localparam logic signed [IN_W-1:0] X_NEG_THREE =
      -$signed(IN_W'(32'd196608));
  localparam logic signed [IN_W-1:0] X_NEG_THREE_POINT_FIVE =
      -$signed(IN_W'(32'd229376));
  localparam logic signed [IN_W-1:0] X_NEG_FOUR = -$signed(IN_W'(32'd262144));
  localparam logic signed [IN_W-1:0] X_NEG_SIXTEEN = -$signed(IN_W'(32'd1048576));
  localparam logic [OUT_W-1:0] Y_ONE = OUT_W'(24'h800000);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_HALF = OUT_W'(24'h4da2cc);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_ONE = OUT_W'(24'h2f16ac);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_ONE_POINT_FIVE = OUT_W'(24'h1c8f87);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_TWO = OUT_W'(24'h1152ab);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_TWO_POINT_FIVE = OUT_W'(24'h0a81c3);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_THREE = OUT_W'(24'h065f6c);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_THREE_POINT_FIVE = OUT_W'(24'h03dd82);
  localparam logic [OUT_W-1:0] Y_EXP_NEG_FOUR = OUT_W'(24'h02582b);
  localparam int unsigned HALF_STEP = 32768;
  localparam int unsigned TAIL_STEP = 786432;

  logic [OUT_W-1:0] y_next;

  function automatic logic [OUT_W-1:0] interp_segment;
    input logic signed [IN_W-1:0] x;
    input logic signed [IN_W-1:0] x_hi;
    input logic [OUT_W-1:0] y_hi;
    input logic [OUT_W-1:0] y_lo;
    input int unsigned step;

    logic [31:0] offset_u;
    logic [47:0] diff_u;
    logic [47:0] drop_u;
    logic [47:0] y_u;
    begin
      offset_u = 32'($signed(x_hi - x));
      diff_u = 48'(y_hi - y_lo);
      drop_u = ((diff_u * 48'(offset_u)) + 48'(step >> 1)) / 48'(step);
      y_u = 48'(y_hi) - drop_u;
      interp_segment = OUT_W'(y_u);
    end
  endfunction

  always_comb begin
    // v0.2 PWL path for S*.16 -> U1.23. Exact debug anchors stay bit-exact;
    // in-between values use linear interpolation to keep generic rows alive.
    if (x_i >= X_ZERO) begin
      y_next = Y_ONE;
    end else if (x_i == X_NEG_HALF) begin
      y_next = Y_EXP_NEG_HALF;
    end else if (x_i == X_NEG_ONE) begin
      y_next = Y_EXP_NEG_ONE;
    end else if (x_i == X_NEG_ONE_POINT_FIVE) begin
      y_next = Y_EXP_NEG_ONE_POINT_FIVE;
    end else if (x_i == X_NEG_TWO) begin
      y_next = Y_EXP_NEG_TWO;
    end else if (x_i == X_NEG_TWO_POINT_FIVE) begin
      y_next = Y_EXP_NEG_TWO_POINT_FIVE;
    end else if (x_i == X_NEG_THREE) begin
      y_next = Y_EXP_NEG_THREE;
    end else if (x_i == X_NEG_THREE_POINT_FIVE) begin
      y_next = Y_EXP_NEG_THREE_POINT_FIVE;
    end else if (x_i == X_NEG_FOUR) begin
      y_next = Y_EXP_NEG_FOUR;
    end else if (x_i <= X_NEG_SIXTEEN) begin
      y_next = '0;
    end else if (x_i > X_NEG_HALF) begin
      y_next = interp_segment(x_i, X_ZERO, Y_ONE, Y_EXP_NEG_HALF, HALF_STEP);
    end else if (x_i > X_NEG_ONE) begin
      y_next = interp_segment(x_i, X_NEG_HALF, Y_EXP_NEG_HALF,
                              Y_EXP_NEG_ONE, HALF_STEP);
    end else if (x_i > X_NEG_ONE_POINT_FIVE) begin
      y_next = interp_segment(x_i, X_NEG_ONE, Y_EXP_NEG_ONE,
                              Y_EXP_NEG_ONE_POINT_FIVE, HALF_STEP);
    end else if (x_i > X_NEG_TWO) begin
      y_next = interp_segment(x_i, X_NEG_ONE_POINT_FIVE,
                              Y_EXP_NEG_ONE_POINT_FIVE, Y_EXP_NEG_TWO,
                              HALF_STEP);
    end else if (x_i > X_NEG_TWO_POINT_FIVE) begin
      y_next = interp_segment(x_i, X_NEG_TWO, Y_EXP_NEG_TWO,
                              Y_EXP_NEG_TWO_POINT_FIVE, HALF_STEP);
    end else if (x_i > X_NEG_THREE) begin
      y_next = interp_segment(x_i, X_NEG_TWO_POINT_FIVE,
                              Y_EXP_NEG_TWO_POINT_FIVE, Y_EXP_NEG_THREE,
                              HALF_STEP);
    end else if (x_i > X_NEG_THREE_POINT_FIVE) begin
      y_next = interp_segment(x_i, X_NEG_THREE, Y_EXP_NEG_THREE,
                              Y_EXP_NEG_THREE_POINT_FIVE, HALF_STEP);
    end else if (x_i > X_NEG_FOUR) begin
      y_next = interp_segment(x_i, X_NEG_THREE_POINT_FIVE,
                              Y_EXP_NEG_THREE_POINT_FIVE, Y_EXP_NEG_FOUR,
                              HALF_STEP);
    end else begin
      y_next = interp_segment(x_i, X_NEG_FOUR, Y_EXP_NEG_FOUR, '0, TAIL_STEP);
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
