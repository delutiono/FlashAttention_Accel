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
  localparam int unsigned LANES_PER_BEAT = BEAT_W / ELEM_W;
  localparam int unsigned BEATS_PER_ROW = D / LANES_PER_BEAT;
  localparam int unsigned BEAT_COUNT_W = (BEATS_PER_ROW <= 1) ? 1 : $clog2(BEATS_PER_ROW);

  logic [BEAT_COUNT_W-1:0] beat_count_q;
  logic signed [ELEM_W-1:0] q_mem [D];

  logic beat_accept;

  assign beat_ready_o = !load_done_o;
  assign beat_accept = beat_valid_i && beat_ready_o;

  always_comb begin
    for (int elem = 0; elem < D; elem++) begin
      q_o[elem] = q_mem[elem];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      beat_count_q <= '0;
      load_done_o <= 1'b0;
      for (int elem = 0; elem < D; elem++) begin
        q_mem[elem] <= '0;
      end
    end else begin
      if (clear_i) begin
        beat_count_q <= '0;
        load_done_o <= 1'b0;
      end else if (beat_accept) begin
        for (int lane = 0; lane < LANES_PER_BEAT; lane++) begin
          q_mem[(beat_count_q * LANES_PER_BEAT) + lane] <=
            beat_data_i[(lane * ELEM_W) +: ELEM_W];
        end

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
