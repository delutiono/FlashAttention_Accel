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
  localparam int unsigned PROD_W = ELEM_W * 2;

  function automatic logic signed [ACC_W-1:0] dot_sum;
    logic signed [ACC_W-1:0] acc;
    logic signed [PROD_W-1:0] prod;
    begin
      acc = '0;
      for (int i = 0; i < D; i++) begin
        prod = $signed(q_i[i]) * $signed(k_i[i]);
        acc += {{(ACC_W-PROD_W){prod[PROD_W-1]}}, prod};
      end
      return acc;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      dot_o   <= '0;
    end else begin
      valid_o <= valid_i;
      dot_o   <= valid_i ? dot_sum() : '0;
    end
  end
endmodule
