`timescale 1ns/1ps

module fa_o_group_store #(
  parameter int unsigned D = fa_pkg::FA_D,
  parameter int unsigned GROUP_ROWS = fa_pkg::FA_Q_GROUP_ROWS,
  parameter int unsigned ELEM_W = fa_pkg::FA_ELEM_W,
  parameter int unsigned AXI_DATA_W = fa_pkg::FA_AXI_DATA_W
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         clear_i,
  input  logic                         final_valid_i,
  input  logic [2:0]                   final_context_i,
  input  logic signed [ELEM_W-1:0]     final_i [D],
  input  logic [GROUP_ROWS-1:0]        active_rows_i,
  output logic                         group_ready_o,
  input  logic                         start_i,
  output logic                         beat_valid_o,
  input  logic                         beat_ready_i,
  output logic [AXI_DATA_W-1:0]        beat_data_o,
  output logic                         beat_last_o,
  output logic                         done_o
);
  localparam int unsigned LANES = AXI_DATA_W / ELEM_W;
  localparam int unsigned ROW_BEATS = D / LANES;
  localparam int unsigned GROUP_BEATS = GROUP_ROWS * ROW_BEATS;
  localparam int unsigned BEAT_W = (GROUP_BEATS <= 1) ? 1 : $clog2(GROUP_BEATS);

  logic signed [ELEM_W-1:0] o_rows_q [GROUP_ROWS][D];
  logic [GROUP_ROWS-1:0] row_valid_q;
  logic streaming_q;
  logic [BEAT_W-1:0] beat_idx_q;
  logic beat_accept;

  assign group_ready_o = ((row_valid_q & active_rows_i) == active_rows_i) && !streaming_q;
  assign beat_valid_o = streaming_q;
  assign beat_last_o = streaming_q && (beat_idx_q == GROUP_BEATS[BEAT_W-1:0] - 1'b1);
  assign beat_accept = beat_valid_o && beat_ready_i;

  always_comb begin
    beat_data_o = '0;
    for (int lane = 0; lane < LANES; lane++) begin
      beat_data_o[(lane * ELEM_W) +: ELEM_W] =
          o_rows_q[beat_idx_q / ROW_BEATS][((beat_idx_q % ROW_BEATS) * LANES) + lane];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      row_valid_q <= '0;
      streaming_q <= 1'b0;
      beat_idx_q <= '0;
      done_o <= 1'b0;
      for (int row = 0; row < GROUP_ROWS; row++) begin
        for (int elem = 0; elem < D; elem++) begin
          o_rows_q[row][elem] <= '0;
        end
      end
    end else begin
      done_o <= 1'b0;

      if (clear_i) begin
        row_valid_q <= '0;
        streaming_q <= 1'b0;
        beat_idx_q <= '0;
      end else begin
        if (final_valid_i && !streaming_q) begin
          row_valid_q[final_context_i] <= 1'b1;
          for (int elem = 0; elem < D; elem++) begin
            o_rows_q[final_context_i][elem] <= final_i[elem];
          end
        end

        if (start_i && group_ready_o) begin
          streaming_q <= 1'b1;
          beat_idx_q <= '0;
        end else if (beat_accept) begin
          if (beat_last_o) begin
            streaming_q <= 1'b0;
            beat_idx_q <= '0;
            row_valid_q <= '0;
            done_o <= 1'b1;
          end else begin
            beat_idx_q <= beat_idx_q + 1'b1;
          end
        end
      end
    end
  end
endmodule
