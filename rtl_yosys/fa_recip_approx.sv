`timescale 1ns/1ps

module fa_recip_approx #(
  parameter IN_W  = 32,
  parameter OUT_W = 32,
  parameter LUT_DEPTH   = 4096,
  parameter LUT_ADDR_W  = 12,
  parameter X_MIN_Q16   = 32768,
  parameter STEP_SHIFT  = 12
) (
  input  logic                clk,
  input  logic                rst_n,
  input  logic                valid_i,
  input  logic [IN_W-1:0]     x_i,
  output logic                valid_o,
  output logic [OUT_W-1:0]    y_o
);

  logic [OUT_W-1:0] recip_lut [0:LUT_DEPTH-1];

  initial begin
    $readmemh("rtl_yosys/recip_lut.hex", recip_lut);
  end

  logic [IN_W-1:0]       x_r;
  logic [LUT_ADDR_W-1:0] lut_addr;
  logic [OUT_W-1:0]      y0;

  logic           valid_stage1;
  logic [IN_W-1:0]  x_stage1;
  logic [OUT_W-1:0] y0_stage1;

  logic [63:0]       prod;
  logic [OUT_W-1:0]  prod_q16;

  logic           valid_stage2;
  logic [OUT_W-1:0] diff_q16;
  logic [OUT_W-1:0] y0_stage2;
  logic [63:0]      nr_prod;

  // Stage 0: LUT lookup
  always_ff @(posedge clk) begin
    x_r <= x_i;
  end

  always_comb begin
    if (x_r < X_MIN_Q16)
      lut_addr = '0;
    else begin
      lut_addr = LUT_ADDR_W'((x_r - X_MIN_Q16) >> STEP_SHIFT);
      if (lut_addr >= LUT_DEPTH)
        lut_addr = LUT_DEPTH - 1;
    end
    y0 = recip_lut[lut_addr];
  end

  // Stage 1: register LUT output, compute x * y0
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_stage1 <= 1'b0;
      x_stage1     <= '0;
      y0_stage1    <= '0;
    end else begin
      valid_stage1 <= valid_i;
      x_stage1     <= x_r;
      y0_stage1    <= y0;
    end
  end

  assign prod = x_stage1 * y0_stage1;
  assign prod_q16 = prod[47:16];

  // Stage 2: Newton-Raphson — y1 = y0 * (2 - x*y0)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_stage2 <= 1'b0;
      diff_q16     <= '0;
      y0_stage2    <= '0;
    end else begin
      valid_stage2 <= valid_stage1;
      diff_q16     <= (33'd131072) - prod_q16;
      y0_stage2    <= y0_stage1;
    end
  end

  assign nr_prod = y0_stage2 * diff_q16;

  // Stage 3: register final output
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      y_o     <= '0;
    end else begin
      valid_o <= valid_stage2;
      if (valid_stage2)
        y_o <= nr_prod[47:16];
    end
  end

endmodule
