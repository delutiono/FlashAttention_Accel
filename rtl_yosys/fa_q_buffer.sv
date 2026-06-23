`timescale 1ns/1ps

module fa_q_buffer #(
  parameter BQ     = 1,
  parameter D      = 64,
  parameter ELEM_W = 16,
  parameter LANES  = 32
) (
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         wr_en_i,
  input  logic [16*D-1:0]              wr_data_i,

  input  logic                         rd_en_i,
  input  logic                         rd_row_i,
  input  logic [2:0]                   rd_chunk_i,
  output logic signed [ELEM_W*LANES-1:0] rd_data_o
);

  logic signed [ELEM_W-1:0] mem [BQ][D];

  localparam CHUNKS = D / LANES;

  always_ff @(posedge clk) begin
    if (wr_en_i)
      for (int i = 0; i < D; i++)
        mem[0][i] <= wr_data_i[i*16 +: 16];
  end

  always_ff @(posedge clk) begin
    if (rd_en_i) begin
      for (int i = 0; i < LANES; i++)
        rd_data_o[i*ELEM_W +: ELEM_W] <= mem[rd_row_i][rd_chunk_i * LANES + i];
    end
  end

endmodule
