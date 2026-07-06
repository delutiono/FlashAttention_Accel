`timescale 1ns/1ps
`default_nettype none

module tb_lowp_page_manager;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic run_enable = 1'b1;
  logic cmd_ready = 1'b1;
  logic cmd_valid;
  logic [1:0] cmd_kind;
  logic cmd_page;
  logic [63:0] cmd_base_addr;
  logic [15:0] cmd_bytes;
  logic [7:0] cmd_tag;

  always #5 clk = ~clk;

  page_manager dut (
    .clk(clk), .rst_n(rst_n), .start(start), .run_enable(run_enable),
    .num_groups(6'd32), .busy(), .done(), .error(),
    .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_kind(cmd_kind),
    .cmd_page(cmd_page), .cmd_base_addr(cmd_base_addr),
    .cmd_bytes(cmd_bytes), .cmd_tag(cmd_tag),
    .dma_done_valid(1'b0), .dma_done_tag(8'd0), .dma_done_error(1'b0),
    .q_base_addr(64'h1000), .k_base_addr(64'h2000),
    .v_base_addr(64'h3000), .o_base_addr(64'h4000),
    .active_q_page(), .active_k_page(), .active_v_page(),
    .active_q_group(), .active_kv_tile(),
    .q_group_ready(), .kv_tile_ready(),
    .scheduler_tile_done(1'b0), .scheduler_group_done(1'b0),
    .q_load_start(), .k_load_start(), .v_load_start(),
    .o_store_start(), .finalize_start(), .update_state_idle(1'b1),
    .task_chain_enable(1'b0), .task_queue_not_empty(1'b0),
    .task_dequeue(), .num_heads(3'd1), .head_stride(32'd0),
    .lowp_int8_mode(1'b1)
  );

  initial begin
    #1000;
    $display("FAIL: timeout");
    $finish;
  end

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    do @(posedge clk); while (!cmd_valid);
    if (cmd_kind !== 2'd0 || cmd_bytes !== 16'd512) begin
      $display("FAIL: lowp Q cmd kind=%0d bytes=%0d", cmd_kind, cmd_bytes);
      $finish;
    end
    $display("PASS lowp page_manager q bytes");
    $finish;
  end
endmodule

`default_nettype wire
