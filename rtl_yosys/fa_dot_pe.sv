`timescale 1ns/1ps

module fa_dot_pe #(
  parameter D     = 64,
  parameter LANES = 32,
  parameter ELEM_W = 16,
  parameter ACC_W  = 48
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         valid_i,
  input  logic                         acc_clr_i,
  input  logic signed [ELEM_W*LANES-1:0] q_i,
  input  logic signed [ELEM_W*LANES-1:0] k_i,
  output logic                         valid_o,
  output logic signed [ACC_W-1:0]      dot_o
);

  localparam STAGES = (D + LANES - 1) / LANES;

  logic signed [32*LANES-1:0] mul_stage;
  logic               valid_mul;
  logic               clr_mul;

  logic signed [ACC_W-1:0] partial_sum;
  logic signed [ACC_W-1:0] acc_q;

  logic               valid_d1, valid_d2;
  logic               acc_valid;

  // Stage 1: multipliers
  always_ff @(posedge clk) begin
    for (int i = 0; i < LANES; i++) begin
      mul_stage[i*32 +: 32] <= q_i[i*ELEM_W +: ELEM_W] * k_i[i*ELEM_W +: ELEM_W];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_mul <= 1'b0;
      clr_mul   <= 1'b0;
    end else begin
      valid_mul <= valid_i;
      clr_mul   <= acc_clr_i;
    end
  end

  // Stage 2: adder tree (combinational)
  always_comb begin
    partial_sum = '0;
    for (int i = 0; i < LANES; i++)
      partial_sum += ACC_W'($signed(mul_stage[i*32 +: 32]));
  end

  // Accumulate across chunks
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_q <= '0;
    end else if (valid_mul) begin
      if (clr_mul)
        acc_q <= partial_sum;
      else
        acc_q <= acc_q + partial_sum;
    end
  end

  // Track how many chunks have been accumulated (aligned with valid_mul)
  logic [$clog2(STAGES)-1:0] chunks_done;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      chunks_done <= '0;
    end else if (valid_mul) begin
      if (clr_mul)
        chunks_done <= 1'd1;
      else
        chunks_done <= chunks_done + 1'd1;
    end
  end

  // Output: valid on last chunk of each dot product
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_d1 <= 1'b0;
      valid_d2 <= 1'b0;
    end else begin
      valid_d1 <= valid_mul && (chunks_done == STAGES - 1);
      valid_d2 <= valid_d1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_valid <= 1'b0;
      valid_o   <= 1'b0;
      dot_o     <= '0;
    end else begin
      acc_valid <= valid_mul;
      valid_o   <= valid_d2;
      if (acc_valid)
        dot_o <= acc_q;
    end
  end

endmodule
