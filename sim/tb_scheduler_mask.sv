`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_mask;
  logic clk;
  logic rst_n;
  logic start;
  logic soft_reset;
  logic done_clear;
  logic busy;
  logic done;
  logic error;
  logic [31:0] cycles;
  fa_state_e state;
  logic [7:0] q_index;
  logic [7:0] kv_tile;
  logic [7:0] k_index;
  logic score_valid;
  logic [4:0] q_group;
  logic [2:0] q_context;
  logic [2:0] kv_row;
  logic score_last;
  logic tile_done;
  logic group_done;

  fa_scheduler #(
    .S_PARAM(8),
    .BQ(1),
    .BK(4)
  ) dut (
    .clk,
    .rst_n,
    .start_i(start),
    .soft_reset_i(soft_reset),
    .done_clear_i(done_clear),
    .causal_en_i(1'b1),
    .q_base_i(64'h1000),
    .k_base_i(64'h2000),
    .v_base_i(64'h3000),
    .o_base_i(64'h4000),
    .stride_bytes_i(32'd128),
    .neg_large_i(16'h8000),
    .scale_i(16'd32),
    .busy_o(busy),
    .done_o(done),
    .error_o(error),
    .cycles_o(cycles),
    .state_o(state),
    .q_index_o(q_index),
    .kv_tile_o(kv_tile),
    .k_index_o(k_index),
    .score_valid_o(score_valid),
    .q_group_o(q_group),
    .q_context_o(q_context),
    .kv_row_o(kv_row),
    .score_last_o(score_last),
    .tile_done_o(tile_done),
    .group_done_o(group_done)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    start = 1'b0;
    soft_reset = 1'b0;
    done_clear = 1'b0;

    repeat (3) tick();
    rst_n = 1'b1;
    tick();

    start = 1'b1;
    tick();
    start = 1'b0;

    for (int guard = 0; guard < 500; guard++) begin
      tick();
      if (state == FA_ST_COMPUTE_TILE) begin
        if (score_valid !== (k_index <= q_index)) begin
          $fatal(1, "mask mismatch q=%0d k=%0d valid=%0b", q_index, k_index, score_valid);
        end
      end
      if (done || error) begin
        break;
      end
    end

    if (!done || error) begin
      $fatal(1, "scheduler mask walk did not complete cleanly");
    end

    $display("tb_scheduler_mask PASS");
    $finish;
  end
endmodule
