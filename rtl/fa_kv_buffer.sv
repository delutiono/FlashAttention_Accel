`timescale 1ns/1ps

module fa_kv_buffer #(
  parameter int unsigned TILE_ROWS = 2,
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned BEAT_W = 64,
  parameter int unsigned ROW_INDEX_W = (TILE_ROWS <= 1) ? 1 : $clog2(TILE_ROWS)
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         clear_i,

  input  logic                         k_valid_i,
  output logic                         k_ready_o,
  input  logic [BEAT_W-1:0]            k_data_i,
  output logic                         k_load_done_o,

  input  logic                         v_valid_i,
  output logic                         v_ready_o,
  input  logic [BEAT_W-1:0]            v_data_i,
  output logic                         v_load_done_o,

  input  logic [ROW_INDEX_W-1:0]       row_index_i,
  output logic signed [ELEM_W-1:0]     k_o [D],
  output logic signed [ELEM_W-1:0]     v_o [D]
);
  localparam int unsigned LANES_PER_BEAT = BEAT_W / ELEM_W;
  localparam int unsigned BEATS_PER_ROW = D / LANES_PER_BEAT;
  localparam int unsigned BEAT_COUNT_W = (BEATS_PER_ROW <= 1) ? 1 : $clog2(BEATS_PER_ROW);
  localparam int unsigned ROW_COUNT_W = (TILE_ROWS <= 1) ? 1 : $clog2(TILE_ROWS);

  logic [BEAT_COUNT_W-1:0] k_beat_count_q;
  logic [ROW_COUNT_W-1:0]  k_row_count_q;
  logic [BEAT_COUNT_W-1:0] v_beat_count_q;
  logic [ROW_COUNT_W-1:0]  v_row_count_q;

  logic signed [ELEM_W-1:0] k_mem [TILE_ROWS][D];
  logic signed [ELEM_W-1:0] v_mem [TILE_ROWS][D];

  logic k_accept;
  logic v_accept;

  assign k_ready_o = !k_load_done_o;
  assign v_ready_o = !v_load_done_o;
  assign k_accept = k_valid_i && k_ready_o;
  assign v_accept = v_valid_i && v_ready_o;

  always_comb begin
    for (int elem = 0; elem < D; elem++) begin
      k_o[elem] = k_mem[row_index_i][elem];
      v_o[elem] = v_mem[row_index_i][elem];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      k_beat_count_q <= '0;
      k_row_count_q <= '0;
      v_beat_count_q <= '0;
      v_row_count_q <= '0;
      k_load_done_o <= 1'b0;
      v_load_done_o <= 1'b0;
      for (int row = 0; row < TILE_ROWS; row++) begin
        for (int elem = 0; elem < D; elem++) begin
          k_mem[row][elem] <= '0;
          v_mem[row][elem] <= '0;
        end
      end
    end else begin
      if (clear_i) begin
        k_beat_count_q <= '0;
        k_row_count_q <= '0;
        v_beat_count_q <= '0;
        v_row_count_q <= '0;
        k_load_done_o <= 1'b0;
        v_load_done_o <= 1'b0;
      end else begin
        if (k_accept) begin
          for (int lane = 0; lane < LANES_PER_BEAT; lane++) begin
            k_mem[k_row_count_q][(k_beat_count_q * LANES_PER_BEAT) + lane] <=
              k_data_i[(lane * ELEM_W) +: ELEM_W];
          end

          if (k_beat_count_q == BEATS_PER_ROW[BEAT_COUNT_W-1:0] - 1'b1) begin
            k_beat_count_q <= '0;
            if (k_row_count_q == TILE_ROWS[ROW_COUNT_W-1:0] - 1'b1) begin
              k_row_count_q <= '0;
              k_load_done_o <= 1'b1;
            end else begin
              k_row_count_q <= k_row_count_q + 1'b1;
            end
          end else begin
            k_beat_count_q <= k_beat_count_q + 1'b1;
          end
        end

        if (v_accept) begin
          for (int lane = 0; lane < LANES_PER_BEAT; lane++) begin
            v_mem[v_row_count_q][(v_beat_count_q * LANES_PER_BEAT) + lane] <=
              v_data_i[(lane * ELEM_W) +: ELEM_W];
          end

          if (v_beat_count_q == BEATS_PER_ROW[BEAT_COUNT_W-1:0] - 1'b1) begin
            v_beat_count_q <= '0;
            if (v_row_count_q == TILE_ROWS[ROW_COUNT_W-1:0] - 1'b1) begin
              v_row_count_q <= '0;
              v_load_done_o <= 1'b1;
            end else begin
              v_row_count_q <= v_row_count_q + 1'b1;
            end
          end else begin
            v_beat_count_q <= v_beat_count_q + 1'b1;
          end
        end
      end
    end
  end
endmodule
