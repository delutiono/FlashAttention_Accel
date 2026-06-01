`timescale 1ns/1ps

import fa_pkg::*;

module tb_scheduler;
  localparam int unsigned BK = 32;

  logic clk;
  logic rst_n;
  logic start;
  logic soft_reset;
  logic done_clear;
  logic causal_en;
  logic [63:0] q_base;
  logic [63:0] k_base;
  logic [63:0] v_base;
  logic [63:0] o_base;
  logic [31:0] stride_bytes;
  logic [15:0] neg_large;
  logic [15:0] scale;
  logic busy;
  logic done;
  logic error;
  logic [31:0] cycles;
  fa_state_e state;
  logic [7:0] q_index;
  logic [7:0] kv_tile;

  fa_scheduler #(
    .BK(BK)
  ) dut (
    .clk,
    .rst_n,
    .start_i(start),
    .soft_reset_i(soft_reset),
    .done_clear_i(done_clear),
    .causal_en_i(causal_en),
    .q_base_i(q_base),
    .k_base_i(k_base),
    .v_base_i(v_base),
    .o_base_i(o_base),
    .stride_bytes_i(stride_bytes),
    .neg_large_i(neg_large),
    .scale_i(scale),
    .busy_o(busy),
    .done_o(done),
    .error_o(error),
    .cycles_o(cycles),
    .state_o(state),
    .q_index_o(q_index),
    .kv_tile_o(kv_tile)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  initial begin
    rst_n = 1'b0;
    start = 1'b0;
    soft_reset = 1'b0;
    done_clear = 1'b0;
    causal_en = 1'b1;
    q_base = 64'h1000;
    k_base = 64'h2000;
    v_base = 64'h3000;
    o_base = 64'h4000;
    stride_bytes = 32'd128;
    neg_large = 16'h8000;
    scale = 16'd32;

    repeat (3) tick();
    rst_n = 1'b1;
    tick();

    start = 1'b1;
    tick();
    start = 1'b0;

    tick();
    if (!busy || state != FA_ST_LOAD_Q) begin
      $fatal(1, "scheduler did not enter LOAD_Q after CHECK_CFG");
    end

    repeat (10) tick();
    if (!busy || done || error) begin
      $fatal(1, "scheduler finished before walking the first q row");
    end
    if (q_index != 8'd0) begin
      $fatal(1, "q_index advanced too early: %0d", q_index);
    end

    repeat (6000) begin
      if (done || error) begin
        break;
      end
      tick();
    end

    if (!done || error || busy) begin
      $fatal(1, "scheduler did not complete cleanly");
    end
    if (q_index != 8'd255) begin
      $fatal(1, "final q_index mismatch: %0d", q_index);
    end

    done_clear = 1'b1;
    tick();
    done_clear = 1'b0;
    if (done) begin
      $fatal(1, "done did not clear");
    end

    stride_bytes = 32'd0;
    start = 1'b1;
    tick();
    start = 1'b0;
    repeat (4) tick();
    if (!error || busy) begin
      $fatal(1, "bad stride did not raise error");
    end

    soft_reset = 1'b1;
    tick();
    soft_reset = 1'b0;
    if (error || busy || done || state != FA_ST_IDLE) begin
      $fatal(1, "soft reset did not clear scheduler");
    end

    $display("tb_scheduler PASS");
    $finish;
  end
endmodule
