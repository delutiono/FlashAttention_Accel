`timescale 1ns/1ps

module fa_dot_pe #(
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned ACC_W = 48,
  parameter int unsigned DOT_LANES = 16
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         valid_i,
  input  logic signed [ELEM_W-1:0]     q_i [D],
  input  logic signed [ELEM_W-1:0]     k_i [D],
  output logic                         ready_o,
  output logic                         valid_o,
  output logic signed [ACC_W-1:0]      dot_o
);
  localparam int unsigned PROD_W = ELEM_W * 2;
  localparam int unsigned DOT_LATENCY_CYCLES = (D + DOT_LANES - 1) / DOT_LANES;
  localparam int unsigned CHUNK_IDX_W = (DOT_LATENCY_CYCLES <= 1) ? 1 : $clog2(DOT_LATENCY_CYCLES);

  logic signed [ELEM_W-1:0] q_hold_q [D];
  logic signed [ELEM_W-1:0] k_hold_q [D];
  logic signed [ACC_W-1:0] prod_s1_q [DOT_LANES];
  logic signed [ACC_W-1:0] chunk_sum_w;
  logic signed [ACC_W-1:0] dot_acc_q;
  logic [CHUNK_IDX_W-1:0] chunk_idx_q;
  logic busy_q;
  logic accept_w;
  logic last_chunk_w;

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

  assign ready_o = rst_n && !busy_q;
  assign accept_w = valid_i && ready_o;
  assign last_chunk_w = (chunk_idx_q == CHUNK_IDX_W'(DOT_LATENCY_CYCLES - 1));

  always_comb begin
    chunk_sum_w = '0;
    for (int lane = 0; lane < DOT_LANES; lane++) begin
      int unsigned idx;
      idx = (int'(chunk_idx_q) * DOT_LANES) + lane;
      if (idx < D) begin
        prod_s1_q[lane] = product_ext(q_hold_q[idx], k_hold_q[idx]);
      end else begin
        prod_s1_q[lane] = '0;
      end
      chunk_sum_w += prod_s1_q[lane];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0;
      chunk_idx_q <= '0;
      dot_acc_q <= '0;
      valid_o <= 1'b0;
      dot_o <= '0;
      for (int lane = 0; lane < D; lane++) begin
        q_hold_q[lane] <= '0;
        k_hold_q[lane] <= '0;
      end
    end else begin
      valid_o <= 1'b0;

      if (accept_w) begin
        busy_q <= 1'b1;
        chunk_idx_q <= '0;
        dot_acc_q <= '0;
        for (int lane = 0; lane < D; lane++) begin
          q_hold_q[lane] <= q_i[lane];
          k_hold_q[lane] <= k_i[lane];
        end
      end else if (busy_q) begin
        if (last_chunk_w) begin
          dot_o <= dot_acc_q + chunk_sum_w;
          valid_o <= 1'b1;
          busy_q <= 1'b0;
          chunk_idx_q <= '0;
          dot_acc_q <= '0;
        end else begin
          dot_acc_q <= dot_acc_q + chunk_sum_w;
          chunk_idx_q <= chunk_idx_q + 1'b1;
        end
      end
    end
  end
endmodule
