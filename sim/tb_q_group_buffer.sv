`timescale 1ns/1ps

module tb_q_group_buffer;
  import fa_pkg::*;

  localparam int unsigned D = FA_D;
  localparam int unsigned ELEM_W = FA_ELEM_W;
  localparam int unsigned BEAT_W = FA_AXI_DATA_W;
  localparam int unsigned GROUP_ROWS = FA_Q_GROUP_ROWS;
  localparam int unsigned LANES_PER_BEAT = BEAT_W / ELEM_W;
  localparam int unsigned BEATS_PER_ROW = FA_ROW_BEATS;
  localparam int unsigned TOTAL_GROUP_BEATS = GROUP_ROWS * BEATS_PER_ROW;
  localparam int unsigned ROW_INDEX_W = $clog2(GROUP_ROWS);

  logic clk;
  logic rst_n;
  logic clear;
  logic beat_valid;
  logic beat_ready;
  logic [BEAT_W-1:0] beat_data;
  logic load_done;
  logic [ROW_INDEX_W-1:0] row_index;
  logic signed [ELEM_W-1:0] q_row [D];

  fa_q_buffer #(
    .D(D),
    .ELEM_W(ELEM_W),
    .BEAT_W(BEAT_W),
    .GROUP_ROWS(GROUP_ROWS)
  ) dut (
    .clk,
    .rst_n,
    .clear_i(clear),
    .beat_valid_i(beat_valid),
    .beat_ready_o(beat_ready),
    .beat_data_i(beat_data),
    .row_index_i(row_index),
    .load_done_o(load_done),
    .q_o(q_row)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic fail(input string message);
    begin
      $error("%s", message);
      $fatal(1);
    end
  endtask

  function automatic logic [BEAT_W-1:0] pack_q_beat(
    input int unsigned row,
    input int unsigned beat
  );
    logic [BEAT_W-1:0] data_word;
    logic [ELEM_W-1:0] lane_value;
    begin
      data_word = '0;
      for (int lane = 0; lane < LANES_PER_BEAT; lane++) begin
        lane_value = 16'(16'h1000 + (row * 16'h0100) + (beat * LANES_PER_BEAT) + lane);
        data_word[(lane * ELEM_W) +: ELEM_W] = lane_value;
      end
      return data_word;
    end
  endfunction

  task automatic send_beat(input logic [BEAT_W-1:0] data);
    begin
      @(negedge clk);
      if (!beat_ready) fail("Q group buffer deasserted ready before group completed");
      beat_valid = 1'b1;
      beat_data = data;
      @(negedge clk);
      beat_valid = 1'b0;
      beat_data = '0;
    end
  endtask

  task automatic check_row(input int unsigned row);
    logic [ELEM_W-1:0] expected;
    begin
      row_index = row[ROW_INDEX_W-1:0];
      repeat (3) @(negedge clk);
      for (int elem = 0; elem < D; elem++) begin
        expected = 16'(16'h1000 + (row * 16'h0100) + elem);
        if (q_row[elem] !== expected) begin
          $fatal(1, "Q row %0d elem %0d mismatch got=0x%04h expected=0x%04h",
                 row, elem, q_row[elem], expected);
        end
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    clear = 1'b0;
    beat_valid = 1'b0;
    beat_data = '0;
    row_index = '0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);
    if (load_done || !beat_ready) fail("Q group buffer did not reset ready");

    for (int row = 0; row < GROUP_ROWS; row++) begin
      for (int beat = 0; beat < BEATS_PER_ROW; beat++) begin
        send_beat(pack_q_beat(row, beat));
        if (((row * BEATS_PER_ROW) + beat < TOTAL_GROUP_BEATS - 1) && load_done) begin
          fail("Q group load_done asserted before final group beat");
        end
      end
    end

    @(negedge clk);
    if (!load_done) fail("Q group load_done did not assert after final beat");
    if (beat_ready) fail("Q group buffer stayed ready after group completed");

    for (int row = 0; row < GROUP_ROWS; row++) begin
      check_row(row);
    end

    @(negedge clk);
    clear = 1'b1;
    @(negedge clk);
    clear = 1'b0;
    if (load_done || !beat_ready) fail("Q group clear did not re-arm buffer");

    $display("tb_q_group_buffer PASS");
    $finish;
  end

  initial begin
    #200000;
    fail("timeout");
  end
endmodule
