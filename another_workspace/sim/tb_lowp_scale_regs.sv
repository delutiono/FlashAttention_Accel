`timescale 1ns/1ps
`default_nettype none

module tb_lowp_scale_regs;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [11:0] awaddr = 12'd0;
  logic awvalid = 1'b0;
  logic awready;
  logic [31:0] wdata = 32'd0;
  logic [3:0] wstrb = 4'hf;
  logic wvalid = 1'b0;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic bready = 1'b1;
  logic [11:0] araddr = 12'd0;
  logic arvalid = 1'b0;
  logic arready;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready = 1'b1;
  logic [15:0] lowp_q_scale;
  logic [15:0] lowp_k_scale;
  logic [15:0] lowp_v_scale;

  always #5 clk = ~clk;

  axi_lite_regs dut (
    .clk(clk), .rst_n(rst_n),
    .s_awaddr(awaddr), .s_awvalid(awvalid), .s_awready(awready),
    .s_wdata(wdata), .s_wstrb(wstrb), .s_wvalid(wvalid), .s_wready(wready),
    .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
    .s_araddr(araddr), .s_arvalid(arvalid), .s_arready(arready),
    .s_rdata(rdata), .s_rresp(rresp), .s_rvalid(rvalid), .s_rready(rready),
    .start_pulse(), .soft_reset_pulse(), .irq_enable(), .irq_pending(),
    .causal_enable(), .q_base_addr(), .k_base_addr(),
    .v_base_addr(), .o_base_addr(), .stride_bytes(),
    .neg_large(), .score_scale(),
    .task_busy(1'b0), .task_done(1'b0), .task_error(1'b0),
    .perf_read_data(32'd0),
    .lowp_mode(), .lowp_block_rows(),
    .q_scale_base_addr(), .k_scale_base_addr(), .v_scale_base_addr(),
    .active_q_group(6'd3), .active_kv_tile(6'd4),
    .lowp_q_scale(lowp_q_scale),
    .lowp_k_scale(lowp_k_scale),
    .lowp_v_scale(lowp_v_scale)
  );

  task axil_write(input [11:0] addr, input [31:0] data);
    begin
      @(negedge clk);
      awaddr = addr; awvalid = 1'b1;
      do @(posedge clk); while (!awready);
      @(negedge clk);
      awvalid = 1'b0;
      wdata = data; wvalid = 1'b1;
      do @(posedge clk); while (!wready);
      @(negedge clk);
      wvalid = 1'b0;
      while (!bvalid) @(posedge clk);
    end
  endtask

  initial begin
    #2000;
    $display("FAIL: timeout");
    $finish;
  end

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    axil_write(12'h07C, {24'd0, 2'd0, 6'd3});
    axil_write(12'h080, 32'h0000_4000);
    axil_write(12'h07C, {24'd0, 2'd1, 6'd4});
    axil_write(12'h080, 32'h0000_8000);
    axil_write(12'h07C, {24'd0, 2'd2, 6'd4});
    axil_write(12'h080, 32'h0000_2000);

    repeat (2) @(posedge clk);
    if (lowp_q_scale !== 16'h4000 || lowp_k_scale !== 16'h8000 || lowp_v_scale !== 16'h2000) begin
      $display("FAIL: scales q=%h k=%h v=%h", lowp_q_scale, lowp_k_scale, lowp_v_scale);
      $finish;
    end
    $display("PASS lowp scale regs");
    $finish;
  end
endmodule

`default_nettype wire
