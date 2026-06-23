`timescale 1ns/1ps

module fa_kv_buffer #(
  parameter BK     = 32,
  parameter D      = 64,
  parameter ELEM_W = 16,
  parameter LANES  = 32
) (
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         wr_en_i,
  input  logic [4:0]                   wr_row_i,
  input  logic signed [ELEM_W*D-1:0]   wr_k_data_i,
  input  logic signed [ELEM_W*D-1:0]   wr_v_data_i,

  input  logic                         rd_en_i,
  input  logic [4:0]                   rd_row_i,
  input  logic [2:0]                   rd_chunk_i,
  output logic signed [ELEM_W*LANES-1:0] rd_k_data_o,
  output logic signed [ELEM_W*LANES-1:0] rd_v_data_o
);

  logic signed [ELEM_W-1:0] k_mem [BK][D];
  logic signed [ELEM_W-1:0] v_mem [BK][D];

  localparam CHUNKS = D / LANES;

  always_ff @(posedge clk) begin
    if (wr_en_i) begin
      for (int i = 0; i < D; i++) begin
        k_mem[wr_row_i][i] <= wr_k_data_i[i*ELEM_W +: ELEM_W];
        v_mem[wr_row_i][i] <= wr_v_data_i[i*ELEM_W +: ELEM_W];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rd_en_i) begin
      for (int i = 0; i < LANES; i++) begin
        rd_k_data_o[i*ELEM_W +: ELEM_W] <= k_mem[rd_row_i][rd_chunk_i * LANES + i];
        rd_v_data_o[i*ELEM_W +: ELEM_W] <= v_mem[rd_row_i][rd_chunk_i * LANES + i];
      end
    end
  end

endmodule
