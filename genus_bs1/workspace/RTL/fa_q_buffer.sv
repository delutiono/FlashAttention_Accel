`timescale 1ns/1ps

module fa_q_buffer #(
  parameter int unsigned D = 64,
  parameter int unsigned ELEM_W = 16,
  parameter int unsigned BEAT_W = 64
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         clear_i,

  input  logic                         beat_valid_i,
  output logic                         beat_ready_o,
  input  logic [BEAT_W-1:0]            beat_data_i,

  output logic                         load_done_o,
  output logic signed [ELEM_W-1:0]     q_o [D]
);
  localparam int unsigned SRAM_BANK_W = 64;
  localparam int unsigned LANES_PER_BANK = SRAM_BANK_W / ELEM_W;
  localparam int unsigned LANES_PER_BEAT = BEAT_W / ELEM_W;
  localparam int unsigned BANKS_PER_ROW = D / LANES_PER_BANK;
  localparam int unsigned BANKS_PER_BEAT = BEAT_W / SRAM_BANK_W;
  localparam int unsigned BEATS_PER_ROW = D / LANES_PER_BEAT;
  localparam int unsigned BEAT_COUNT_W = (BEATS_PER_ROW <= 1) ? 1 : $clog2(BEATS_PER_ROW);

  logic [BEAT_COUNT_W-1:0] beat_count_q;
  logic [SRAM_BANK_W-1:0]   q_bank_data [BANKS_PER_ROW];

  logic beat_accept;

  assign beat_ready_o = !load_done_o;
  assign beat_accept = beat_valid_i && beat_ready_o;

  genvar bank;
  generate
    for (bank = 0; bank < BANKS_PER_ROW; bank++) begin : gen_q_sram_bank
      localparam int unsigned BEAT_SLOT = bank / BANKS_PER_BEAT;
      localparam int unsigned BANK_SLOT = bank % BANKS_PER_BEAT;

      logic bank_write_en;
      logic bank_read_en;

      assign bank_write_en = beat_accept && (beat_count_q == BEAT_COUNT_W'(BEAT_SLOT));
      assign bank_read_en = !bank_write_en;

      // Q row 只有一行，但仍落到 SRAM bank，避免主线 buffer 继续综合成寄存器数组。
      fa_sram_1rw1r_64x64_sky130 u_q_bank (
        .clk       (clk),
        .rst_n     (rst_n),
        .rw_en     (bank_write_en),
        .rw_write  (1'b1),
        .rw_wmask  (8'hff),
        .rw_addr   (6'd0),
        .rw_wdata  (beat_data_i[(BANK_SLOT * SRAM_BANK_W) +: SRAM_BANK_W]),
        .rw_rvalid (),
        .rw_rdata  (),
        .rd_en     (bank_read_en),
        .rd_addr   (6'd0),
        .rd_valid  (),
        .rd_data   (q_bank_data[bank])
      );
    end
  endgenerate

  always_comb begin
    for (int bank_idx = 0; bank_idx < BANKS_PER_ROW; bank_idx++) begin
      for (int lane = 0; lane < LANES_PER_BANK; lane++) begin
        q_o[(bank_idx * LANES_PER_BANK) + lane] =
          q_bank_data[bank_idx][(lane * ELEM_W) +: ELEM_W];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      beat_count_q <= '0;
      load_done_o <= 1'b0;
    end else begin
      if (clear_i) begin
        beat_count_q <= '0;
        load_done_o <= 1'b0;
      end else if (beat_accept) begin
        if (beat_count_q == BEATS_PER_ROW[BEAT_COUNT_W-1:0] - 1'b1) begin
          beat_count_q <= '0;
          load_done_o <= 1'b1;
        end else begin
          beat_count_q <= beat_count_q + 1'b1;
        end
      end
    end
  end
endmodule
