`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler_default_mask;
  logic clk;
  logic rst_n;
  logic start_i;
  logic done_clear_i;
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

  fa_scheduler dut (
    .clk,
    .rst_n,
    .start_i,
    .soft_reset_i(1'b0),
    .done_clear_i,
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

  initial begin
    rst_n = 1'b0;
    start_i = 1'b0;
    done_clear_i = 1'b0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    start_i = 1'b1;
    @(negedge clk);
    start_i = 1'b0;

    wait (state_o == FA_ST_COMPUTE_TILE);
    #1;
    if (q_index_o !== 8'd0 || k_index_o !== 8'd0 || !score_valid_o) begin
      $fatal(1, "default mask first score invalid: q=%0d k=%0d valid=%0b",
             q_index_o, k_index_o, score_valid_o);
    end

    wait (state_o == FA_ST_COMPUTE_TILE && kv_row_o == 3'd1 && q_context_o == 3'd0);
    #1;
    if (q_index_o !== 8'd0 || k_index_o !== 8'd1 || score_valid_o) begin
      $fatal(1, "default group mask failed to suppress future score: q=%0d k=%0d valid=%0b",
             q_index_o, k_index_o, score_valid_o);
    end

    $display("tb_scheduler_default_mask PASS");
    $finish;
  end
endmodule
