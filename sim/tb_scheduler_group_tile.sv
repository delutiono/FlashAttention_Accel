`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_group_tile;
  logic clk;
  logic rst_n;
  logic start_i;
  logic busy_o;
  logic done_o;
  logic error_o;
  logic [31:0] cycles_o;
  fa_state_e state_o;
  logic [7:0] q_index_o;
  logic [7:0] kv_tile_o;
  logic [7:0] k_index_o;
  logic score_valid_o;
  logic [4:0] q_group_o;
  logic [2:0] q_context_o;
  logic [2:0] kv_row_o;
  logic score_last_o;
  logic tile_done_o;
  logic group_done_o;

  int unsigned group1_tile0_scores;
  int unsigned group1_tile1_scores;
  int unsigned group1_last_seen;
  bit saw_group1_tile0_done;
  bit saw_group1_done;

  fa_scheduler #(
    .S_PARAM(16),
    .BQ(FA_Q_GROUP_ROWS),
    .BK(FA_KV_TILE_ROWS)
  ) dut (
    .clk,
    .rst_n,
    .start_i,
    .soft_reset_i(1'b0),
    .done_clear_i(1'b0),
    .causal_en_i(1'b1),
    .q_base_i(64'h1000),
    .k_base_i(64'h2000),
    .v_base_i(64'h3000),
    .o_base_i(64'h4000),
    .stride_bytes_i(32'd128),
    .neg_large_i(16'h8000),
    .scale_i(16'h0100),
    .busy_o,
    .done_o,
    .error_o,
    .cycles_o,
    .state_o,
    .q_index_o,
    .kv_tile_o,
    .k_index_o,
    .score_valid_o,
    .q_group_o,
    .q_context_o,
    .kv_row_o,
    .score_last_o,
    .tile_done_o,
    .group_done_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic fail(input string message);
    begin
      $error("%s", message);
      $fatal(1);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    start_i = 1'b0;
    group1_tile0_scores = 0;
    group1_tile1_scores = 0;
    group1_last_seen = 0;
    saw_group1_tile0_done = 1'b0;
    saw_group1_done = 1'b0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    start_i = 1'b1;
    @(negedge clk);
    start_i = 1'b0;

    for (int guard = 0; guard < 1000; guard++) begin
      @(posedge clk);
      #1;

      if (state_o == FA_ST_COMPUTE_TILE && q_group_o == 5'd1) begin
        if (score_valid_o && kv_tile_o == 8'd0) begin
          group1_tile0_scores++;
          if (q_index_o != {q_group_o, q_context_o}) begin
            fail("global q_index did not match group/context packing");
          end
          if (k_index_o != {kv_tile_o[4:0], kv_row_o}) begin
            fail("global k_index did not match tile/row packing");
          end
        end

        if (score_valid_o && kv_tile_o == 8'd1) begin
          group1_tile1_scores++;
          if (kv_row_o > q_context_o) begin
            fail("causal scheduler emitted a future K row in the diagonal tile");
          end
          if (score_last_o) begin
            group1_last_seen++;
            if (kv_row_o !== q_context_o) fail("score_last asserted away from diagonal");
          end
        end

        if (tile_done_o && kv_tile_o == 8'd0) begin
          saw_group1_tile0_done = 1'b1;
        end
        if (group_done_o) begin
          saw_group1_done = 1'b1;
        end
      end

      if (done_o || error_o) break;
    end

    if (error_o || !done_o) fail("scheduler did not finish cleanly");
    if (group1_tile0_scores != 64) fail("group 1 tile 0 did not emit 64 legal scores");
    if (group1_tile1_scores != 36) fail("group 1 diagonal tile did not emit triangular scores");
    if (group1_last_seen != 8) fail("group 1 did not mark one last score per context");
    if (!saw_group1_tile0_done) fail("did not observe group 1 tile 0 done");
    if (!saw_group1_done) fail("did not observe group 1 done");

    $display("tb_scheduler_group_tile PASS");
    $finish;
  end
endmodule
