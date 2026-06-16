`timescale 1ns/1ps

module fa_compute_core #(
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned DOT_ACC_W = 48
) (
  input  logic                              clk,
  input  logic                              rst_n,
  input  logic                              valid_i,
  input  var logic signed [ELEM_W-1:0]      q_i [D],
  input  var logic signed [ELEM_W-1:0]      k_i [D],
  output logic                              dot_valid_o,
  output logic signed [DOT_ACC_W-1:0]       dot_o
);
  fa_dot_pe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .ACC_W(DOT_ACC_W)
  ) u_dot_pe (
    .clk,
    .rst_n,
    .valid_i,
    .q_i,
    .k_i,
    .valid_o(dot_valid_o),
    .dot_o
  );
endmodule
