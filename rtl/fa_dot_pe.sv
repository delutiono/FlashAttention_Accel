`timescale 1ns/1ps

module fa_dot_pe #(
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned ACC_W = 48
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         valid_i,
  input  var logic signed [ELEM_W-1:0] q_i [D],
  input  var logic signed [ELEM_W-1:0] k_i [D],
  output logic                         valid_o,
  output logic signed [ACC_W-1:0]      dot_o
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      dot_o   <= '0;
    end else begin
      valid_o <= valid_i;
      dot_o   <= '0;
    end
  end
endmodule
