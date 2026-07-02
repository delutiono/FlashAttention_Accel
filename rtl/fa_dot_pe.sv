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
  localparam int unsigned DOT_LATENCY_CYCLES = 2;
  localparam int unsigned SUM_GROUP_SIZE = 4;
  localparam int unsigned SUM_GROUPS = (D + SUM_GROUP_SIZE - 1) / SUM_GROUP_SIZE;

  logic signed [ACC_W-1:0] prod_s1_q [D];
  logic signed [ACC_W-1:0] sum_s2_q [SUM_GROUPS];
  logic valid_s1_q;
  logic valid_s2_q;

  function automatic logic signed [ACC_W-1:0] product_ext(
      input logic signed [ELEM_W-1:0] q,
      input logic signed [ELEM_W-1:0] k
  );
    logic signed [PROD_W-1:0] prod;
    begin
      prod = q * k;
      product_ext = {{(ACC_W-PROD_W){prod[PROD_W-1]}}, prod};
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] sum_product_group(
      input int unsigned group_idx
  );
    logic signed [ACC_W-1:0] acc;
    int unsigned idx;
    begin
      acc = '0;
      for (int lane = 0; lane < SUM_GROUP_SIZE; lane++) begin
        idx = group_idx * SUM_GROUP_SIZE + lane;
        if (idx < D) begin
          acc += prod_s1_q[idx];
        end
      end
      return acc;
    end
  endfunction

  function automatic logic signed [ACC_W-1:0] final_sum;
    logic signed [ACC_W-1:0] acc;
    begin
      acc = '0;
      for (int group = 0; group < SUM_GROUPS; group++) begin
        acc += sum_s2_q[group];
      end
      return acc;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s1_q <= 1'b0;
      valid_s2_q <= 1'b0;
      valid_o    <= 1'b0;
      dot_o      <= '0;
      for (int lane = 0; lane < D; lane++) begin
        prod_s1_q[lane] <= '0;
      end
      for (int group = 0; group < SUM_GROUPS; group++) begin
        sum_s2_q[group] <= '0;
      end
    end else begin
      valid_s1_q <= valid_i;
      valid_s2_q <= valid_s1_q;
      valid_o    <= valid_s2_q;

      for (int lane = 0; lane < D; lane++) begin
        prod_s1_q[lane] <= valid_i ? product_ext(q_i[lane], k_i[lane]) : '0;
      end

      for (int group = 0; group < SUM_GROUPS; group++) begin
        sum_s2_q[group] <= valid_s1_q ? sum_product_group(group) : '0;
      end

      dot_o <= valid_s2_q ? final_sum() : '0;
    end
  end
endmodule
