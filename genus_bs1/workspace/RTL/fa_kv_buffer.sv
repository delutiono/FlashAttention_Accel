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
  localparam int unsigned SRAM_BANK_W = 64;
  localparam int unsigned LANES_PER_BANK = SRAM_BANK_W / ELEM_W;
  localparam int unsigned LANES_PER_BEAT = BEAT_W / ELEM_W;
  localparam int unsigned BANKS_PER_ROW = D / LANES_PER_BANK;
  localparam int unsigned BANKS_PER_BEAT = BEAT_W / SRAM_BANK_W;
  localparam int unsigned BEATS_PER_ROW = D / LANES_PER_BEAT;
  localparam int unsigned BEAT_COUNT_W = (BEATS_PER_ROW <= 1) ? 1 : $clog2(BEATS_PER_ROW);
  localparam int unsigned ROW_COUNT_W = (TILE_ROWS <= 1) ? 1 : $clog2(TILE_ROWS);

  logic [BEAT_COUNT_W-1:0] k_beat_count_q;
  logic [ROW_COUNT_W-1:0]  k_row_count_q;
  logic [BEAT_COUNT_W-1:0] v_beat_count_q;
  logic [ROW_COUNT_W-1:0]  v_row_count_q;

  logic [SRAM_BANK_W-1:0] k_bank_data [BANKS_PER_ROW];
  logic [SRAM_BANK_W-1:0] v_bank_data [BANKS_PER_ROW];

  logic k_accept;
  logic v_accept;

  assign k_ready_o = !k_load_done_o;
  assign v_ready_o = !v_load_done_o;
  assign k_accept = k_valid_i && k_ready_o;
  assign v_accept = v_valid_i && v_ready_o;

  genvar bank;
  generate
    for (bank = 0; bank < BANKS_PER_ROW; bank++) begin : gen_kv_sram_bank
      localparam int unsigned BEAT_SLOT = bank / BANKS_PER_BEAT;
      localparam int unsigned BANK_SLOT = bank % BANKS_PER_BEAT;

      logic k_bank_write_en;
      logic v_bank_write_en;
      logic k_bank_read_en;
      logic v_bank_read_en;

      assign k_bank_write_en = k_accept && (k_beat_count_q == BEAT_COUNT_W'(BEAT_SLOT));
      assign v_bank_write_en = v_accept && (v_beat_count_q == BEAT_COUNT_W'(BEAT_SLOT));
      assign k_bank_read_en = !(k_bank_write_en && (k_row_count_q == ROW_COUNT_W'(row_index_i)));
      assign v_bank_read_en = !(v_bank_write_en && (v_row_count_q == ROW_COUNT_W'(row_index_i)));

      // K/V tile 以 row 为 SRAM 地址、以 4 个 int16 lane 为一个 64-bit bank。
      fa_sram_1rw1r_64x64_sky130 u_k_bank (
        .clk       (clk),
        .rst_n     (rst_n),
        .rw_en     (k_bank_write_en),
        .rw_write  (1'b1),
        .rw_wmask  (8'hff),
        .rw_addr   (6'(k_row_count_q)),
        .rw_wdata  (k_data_i[(BANK_SLOT * SRAM_BANK_W) +: SRAM_BANK_W]),
        .rw_rvalid (),
        .rw_rdata  (),
        .rd_en     (k_bank_read_en),
        .rd_addr   (6'(row_index_i)),
        .rd_valid  (),
        .rd_data   (k_bank_data[bank])
      );

      fa_sram_1rw1r_64x64_sky130 u_v_bank (
        .clk       (clk),
        .rst_n     (rst_n),
        .rw_en     (v_bank_write_en),
        .rw_write  (1'b1),
        .rw_wmask  (8'hff),
        .rw_addr   (6'(v_row_count_q)),
        .rw_wdata  (v_data_i[(BANK_SLOT * SRAM_BANK_W) +: SRAM_BANK_W]),
        .rw_rvalid (),
        .rw_rdata  (),
        .rd_en     (v_bank_read_en),
        .rd_addr   (6'(row_index_i)),
        .rd_valid  (),
        .rd_data   (v_bank_data[bank])
      );
    end
  endgenerate

  always_comb begin
    for (int bank_idx = 0; bank_idx < BANKS_PER_ROW; bank_idx++) begin
      for (int lane = 0; lane < LANES_PER_BANK; lane++) begin
        k_o[(bank_idx * LANES_PER_BANK) + lane] =
          k_bank_data[bank_idx][(lane * ELEM_W) +: ELEM_W];
        v_o[(bank_idx * LANES_PER_BANK) + lane] =
          v_bank_data[bank_idx][(lane * ELEM_W) +: ELEM_W];
      end
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
