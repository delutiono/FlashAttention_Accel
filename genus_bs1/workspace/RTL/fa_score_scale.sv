`timescale 1ns/1ps

module fa_score_scale #(
  parameter int unsigned SCORE_W = 48
) (
  input  logic signed [SCORE_W-1:0] raw_dot_i,
  output logic signed [SCORE_W-1:0] scaled_score_o
);
  // Bring-up v0.1 fixed baseline scale: 1/sqrt(64) = 1/8.
  // This uses a signed arithmetic shift, which truncates positive
  // non-multiples of 8 toward zero and negative non-multiples toward
  // negative infinity. Align with the fixed-point v1.0 project rounding
  // rule when that tie/rounding policy is frozen.
  assign scaled_score_o = raw_dot_i >>> 3;
endmodule
