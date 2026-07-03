`timescale 1ns/1ps

module fa_finalize_vec #(
  parameter int unsigned D = 64,
  parameter int unsigned L_W = 32,
  parameter int unsigned ACC_W = 48,
  parameter int unsigned OUT_W = 16
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         valid_i,
  input  logic [L_W-1:0]               l_i,
  input  logic signed [ACC_W-1:0]      acc_i [D],
  output logic                         valid_o,
  output logic                         div_zero_o,
  output logic signed [OUT_W-1:0]      o_q88_o [D]
);
  localparam int unsigned RECIP_LATENCY = 4;

  logic                         recip_valid;
  logic                         recip_div_zero;
  logic                         div_zero_pipe_q;
  logic [31:0]                  recip_l;
  logic signed [ACC_W-1:0]      acc_pipe [RECIP_LATENCY][D];
  logic                         quant_valid [D];

  fa_recip_approx #(
    .IN_W(L_W),
    .OUT_W(32)
  ) u_recip_approx (
    .clk,
    .rst_n,
    .valid_i,
    .x_i(l_i),
    .valid_o(recip_valid),
    .y_o(recip_l),
    .div_zero_o(recip_div_zero)
  );

  genvar g;
  generate
    for (g = 0; g < D; g++) begin : gen_out_quant
      fa_out_quant #(
        .IN_W(ACC_W),
        .RECIP_W(32),
        .OUT_W(OUT_W)
      ) u_out_quant (
        .clk,
        .rst_n,
        .valid_i(recip_valid),
        .x_i(acc_pipe[RECIP_LATENCY-1][g]),
        .recip_l_i(recip_l),
        .valid_o(quant_valid[g]),
        .y_o(o_q88_o[g])
      );
    end
  endgenerate

  assign valid_o = quant_valid[0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_zero_o <= 1'b0;
      div_zero_pipe_q <= 1'b0;
      for (int stage = 0; stage < RECIP_LATENCY; stage++) begin
        for (int lane = 0; lane < D; lane++) begin
          acc_pipe[stage][lane] <= '0;
        end
      end
    end else begin
      div_zero_pipe_q <= recip_valid && recip_div_zero;
      div_zero_o <= div_zero_pipe_q;
      for (int lane = 0; lane < D; lane++) begin
        acc_pipe[0][lane] <= valid_i ? acc_i[lane] : '0;
      end
      for (int stage = 1; stage < RECIP_LATENCY; stage++) begin
        for (int lane = 0; lane < D; lane++) begin
          acc_pipe[stage][lane] <= acc_pipe[stage-1][lane];
        end
      end
    end
  end
endmodule
