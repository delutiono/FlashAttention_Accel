`timescale 1ns/1ps

module fa_out_quant #(
  parameter int unsigned IN_W = 48,
  parameter int unsigned OUT_W = 16
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         valid_i,
  input  logic signed [IN_W-1:0]       x_i,
  output logic                         valid_o,
  output logic signed [OUT_W-1:0]      y_o
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      y_o     <= '0;
    end else begin
      valid_o <= valid_i;
      y_o     <= x_i[OUT_W-1:0];
    end
  end
endmodule
