`timescale 1ns/1ps

module tb_o_group_store;
  import fa_pkg::*;

  localparam int unsigned GROUP_ROWS = FA_Q_GROUP_ROWS;
  localparam int unsigned D = FA_D;
  localparam int unsigned ELEM_W = FA_ELEM_W;
  localparam int unsigned LANES = FA_AXI_DATA_W / FA_ELEM_W;
  localparam int unsigned ROW_BEATS = FA_ROW_BEATS;
  localparam int unsigned GROUP_BEATS = FA_GROUP_BEATS;

  logic clk;
  logic rst_n;
  logic clear;
  logic final_valid;
  logic [2:0] final_context;
  logic signed [ELEM_W-1:0] final_row [D];
  logic [GROUP_ROWS-1:0] active_rows;
  logic group_ready;
  logic start;
  logic beat_valid;
  logic beat_ready;
  logic [FA_AXI_DATA_W-1:0] beat_data;
  logic beat_last;
  logic done;

  int unsigned accepted_beats;
  logic [FA_AXI_DATA_W-1:0] held_last_data;

  fa_o_group_store dut (
    .clk,
    .rst_n,
    .clear_i(clear),
    .final_valid_i(final_valid),
    .final_context_i(final_context),
    .final_i(final_row),
    .active_rows_i(active_rows),
    .group_ready_o(group_ready),
    .start_i(start),
    .beat_valid_o(beat_valid),
    .beat_ready_i(beat_ready),
    .beat_data_o(beat_data),
    .beat_last_o(beat_last),
    .done_o(done)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic fail(input string message);
    begin
      $error("%s", message);
      $fatal(1);
    end
  endtask

  function automatic logic [ELEM_W-1:0] expected_elem(
    input int unsigned row,
    input int unsigned elem
  );
    begin
      return ELEM_W'(16'h3000 + (row * 16'h0100) + elem);
    end
  endfunction

  function automatic logic [FA_AXI_DATA_W-1:0] expected_beat(input int unsigned beat);
    logic [FA_AXI_DATA_W-1:0] data;
    int unsigned row;
    int unsigned beat_in_row;
    begin
      data = '0;
      row = beat / ROW_BEATS;
      beat_in_row = beat % ROW_BEATS;
      for (int lane = 0; lane < LANES; lane++) begin
        data[(lane * ELEM_W) +: ELEM_W] =
            expected_elem(row, (beat_in_row * LANES) + lane);
      end
      return data;
    end
  endfunction

  task automatic push_final(input int unsigned row);
    begin
      @(negedge clk);
      final_context = row[2:0];
      for (int elem = 0; elem < D; elem++) begin
        final_row[elem] = expected_elem(row, elem);
      end
      final_valid = 1'b1;
      @(negedge clk);
      final_valid = 1'b0;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    clear = 1'b0;
    final_valid = 1'b0;
    final_context = '0;
    active_rows = '1;
    start = 1'b0;
    beat_ready = 1'b0;
    accepted_beats = 0;
    held_last_data = '0;
    for (int elem = 0; elem < D; elem++) begin
      final_row[elem] = '0;
    end

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    for (int row = 0; row < GROUP_ROWS; row++) begin
      push_final(row);
      if ((row < GROUP_ROWS - 1) && group_ready) begin
        fail("group_ready asserted before all rows arrived");
      end
    end

    @(negedge clk);
    if (!group_ready) fail("group_ready did not assert after 8 final rows");

    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    beat_ready = 1'b0;

    for (int beat = 0; beat < GROUP_BEATS; beat++) begin
      wait (beat_valid);
      #1;
      if (beat_data !== expected_beat(beat)) begin
        $fatal(1, "beat %0d data mismatch got=0x%0x expected=0x%0x",
               beat, beat_data, expected_beat(beat));
      end
      if (beat_last !== (beat == GROUP_BEATS - 1)) begin
        fail("beat_last mismatch");
      end

      if (beat == GROUP_BEATS - 1) begin
        held_last_data = beat_data;
        repeat (2) begin
          @(negedge clk);
          beat_ready = 1'b0;
          #1;
          if (!beat_valid || !beat_last) fail("last beat was not held during stall");
          if (beat_data !== held_last_data) fail("last beat data changed while stalled");
        end
      end

      @(negedge clk);
      beat_ready = 1'b1;
      if (beat == GROUP_BEATS - 1) begin
        @(posedge clk);
        #1;
        if (!done) fail("done did not assert after final beat");
        @(negedge clk);
        beat_ready = 1'b0;
      end else begin
        @(negedge clk);
        beat_ready = 1'b0;
      end
      accepted_beats++;
    end

    if (accepted_beats != GROUP_BEATS) fail("did not accept exactly 64 beats");
    if (group_ready) fail("group_ready stayed high after write completed");

    $display("tb_o_group_store PASS");
    $finish;
  end

  initial begin
    #200000;
    fail("timeout");
  end
endmodule
