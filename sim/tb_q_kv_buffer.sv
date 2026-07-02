`timescale 1ns/1ps

module tb_q_kv_buffer;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned TILE_ROWS = 2;
  localparam int unsigned LANES_PER_BEAT = 4;
  localparam int unsigned BEATS_PER_ROW = 16;
  localparam int unsigned TOTAL_TILE_BEATS = TILE_ROWS * BEATS_PER_ROW;

  logic clk;
  logic rst_n;

  logic q_clear;
  logic q_valid;
  logic q_ready;
  logic [63:0] q_data;
  logic q_done;
  logic signed [ELEM_W-1:0] q_row [D];

  logic kv_clear;
  logic k_valid;
  logic k_ready;
  logic [63:0] k_data;
  logic k_done;
  logic v_valid;
  logic v_ready;
  logic [63:0] v_data;
  logic v_done;
  logic [$clog2(TILE_ROWS)-1:0] row_index;
  logic signed [ELEM_W-1:0] k_row [D];
  logic signed [ELEM_W-1:0] v_row [D];

  fa_q_buffer #(
    .D(D),
    .ELEM_W(ELEM_W),
    .GROUP_ROWS(1)
  ) u_q_buffer (
    .clk,
    .rst_n,
    .clear_i(q_clear),
    .beat_valid_i(q_valid),
    .beat_ready_o(q_ready),
    .beat_data_i(q_data),
    .row_index_i('0),
    .load_done_o(q_done),
    .q_o(q_row)
  );

  fa_kv_buffer #(
    .TILE_ROWS(TILE_ROWS),
    .D(D),
    .ELEM_W(ELEM_W)
  ) u_kv_buffer (
    .clk,
    .rst_n,
    .clear_i(kv_clear),
    .k_valid_i(k_valid),
    .k_ready_o(k_ready),
    .k_data_i(k_data),
    .k_load_done_o(k_done),
    .v_valid_i(v_valid),
    .v_ready_o(v_ready),
    .v_data_i(v_data),
    .v_load_done_o(v_done),
    .row_index_i(row_index),
    .k_o(k_row),
    .v_o(v_row)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic fail(input string message);
    begin
      $error("%s", message);
      $fatal(1);
    end
  endtask

  function automatic logic [63:0] pack_lanes(input int unsigned base);
    logic [63:0] data_word;
    logic [ELEM_W-1:0] lane_value;
    begin
      data_word = '0;
      for (int lane = 0; lane < LANES_PER_BEAT; lane++) begin
        lane_value = base + lane;
        data_word[(lane * ELEM_W) +: ELEM_W] = lane_value;
      end
      return data_word;
    end
  endfunction

  task automatic send_q_beat(input logic [63:0] data);
    begin
      @(negedge clk);
      if (!q_ready) fail("Q buffer was not ready before row completed");
      q_valid = 1'b1;
      q_data = data;
      @(negedge clk);
      q_valid = 1'b0;
      q_data = '0;
    end
  endtask

  task automatic send_k_beat(input logic [63:0] data);
    begin
      @(negedge clk);
      if (!k_ready) fail("K buffer was not ready before tile completed");
      k_valid = 1'b1;
      k_data = data;
      @(negedge clk);
      k_valid = 1'b0;
      k_data = '0;
    end
  endtask

  task automatic send_v_beat(input logic [63:0] data);
    begin
      @(negedge clk);
      if (!v_ready) fail("V buffer was not ready before tile completed");
      v_valid = 1'b1;
      v_data = data;
      @(negedge clk);
      v_valid = 1'b0;
      v_data = '0;
    end
  endtask

  task automatic check_q_row;
    logic [ELEM_W-1:0] expected;
    begin
      for (int elem = 0; elem < D; elem++) begin
        expected = 16'h1000 + elem;
        if (q_row[elem] !== expected) begin
          $fatal(1, "Q lane %0d mismatch got=0x%04h expected=0x%04h",
                 elem, q_row[elem], expected);
        end
      end
    end
  endtask

  task automatic check_kv_row(
    input int unsigned row,
    input int unsigned k_base,
    input int unsigned v_base
  );
    logic [ELEM_W-1:0] expected_k;
    logic [ELEM_W-1:0] expected_v;
    begin
      row_index = row[$clog2(TILE_ROWS)-1:0];
      repeat (3) @(negedge clk);
      for (int elem = 0; elem < D; elem++) begin
        expected_k = k_base + elem;
        expected_v = v_base + elem;
        if (k_row[elem] !== expected_k) begin
          $fatal(1, "K row %0d lane %0d mismatch got=0x%04h expected=0x%04h",
                 row, elem, k_row[elem], expected_k);
        end
        if (v_row[elem] !== expected_v) begin
          $fatal(1, "V row %0d lane %0d mismatch got=0x%04h expected=0x%04h",
                 row, elem, v_row[elem], expected_v);
        end
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    q_clear = 1'b0;
    q_valid = 1'b0;
    q_data = '0;
    kv_clear = 1'b0;
    k_valid = 1'b0;
    k_data = '0;
    v_valid = 1'b0;
    v_data = '0;
    row_index = '0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    if (q_done || k_done || v_done) fail("load_done asserted after reset");

    for (int beat = 0; beat < BEATS_PER_ROW; beat++) begin
      send_q_beat(pack_lanes(16'h1000 + (beat * LANES_PER_BEAT)));
      if ((beat < BEATS_PER_ROW - 1) && q_done) begin
        fail("Q load_done asserted before final beat");
      end
    end
    @(negedge clk);
    if (!q_done) fail("Q load_done did not assert after final beat");
    if (q_ready) fail("Q buffer stayed ready after row completed");
    repeat (3) @(negedge clk);
    check_q_row();

    @(negedge clk);
    q_clear = 1'b1;
    @(negedge clk);
    q_clear = 1'b0;
    if (q_done || !q_ready) fail("Q clear did not re-arm buffer");

    for (int beat = 0; beat < TOTAL_TILE_BEATS; beat++) begin
      send_k_beat(pack_lanes(16'h2000 + (beat * LANES_PER_BEAT)));
      if ((beat < TOTAL_TILE_BEATS - 1) && k_done) begin
        fail("K load_done asserted before final tile beat");
      end
    end
    @(negedge clk);
    if (!k_done) fail("K load_done did not assert after tile load");
    if (k_ready) fail("K buffer stayed ready after tile completed");

    for (int beat = 0; beat < TOTAL_TILE_BEATS; beat++) begin
      send_v_beat(pack_lanes(16'h4000 + (beat * LANES_PER_BEAT)));
      if ((beat < TOTAL_TILE_BEATS - 1) && v_done) begin
        fail("V load_done asserted before final tile beat");
      end
    end
    @(negedge clk);
    if (!v_done) fail("V load_done did not assert after tile load");
    if (v_ready) fail("V buffer stayed ready after tile completed");

    check_kv_row(0, 16'h2000, 16'h4000);
    check_kv_row(1, 16'h2040, 16'h4040);

    @(negedge clk);
    kv_clear = 1'b1;
    @(negedge clk);
    kv_clear = 1'b0;
    if (k_done || v_done || !k_ready || !v_ready) fail("KV clear did not re-arm buffers");

    $display("tb_q_kv_buffer PASS");
    $finish;
  end

  initial begin
    #200000;
    fail("timeout");
  end
endmodule
