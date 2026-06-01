`timescale 1ns/1ps

import fa_pkg::*;

module tb_regfile;
  logic clk;
  logic rst_n;

  logic [11:0] awaddr;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  logic [11:0] araddr;
  logic        arvalid;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  logic        start_pulse;
  logic        soft_reset_pulse;
  logic        done_clear_pulse;
  logic        irq_en;
  logic        causal_en;
  logic [63:0] q_base;
  logic [63:0] k_base;
  logic [63:0] v_base;
  logic [63:0] o_base;
  logic [31:0] stride_bytes;
  logic [15:0] neg_large;
  logic [15:0] scale;
  logic [31:0] cycles_i;
  logic        busy_i;
  logic        done_i;
  logic        error_i;

  fa_regfile dut (
    .clk,
    .rst_n,
    .s_axil_awaddr(awaddr),
    .s_axil_awvalid(awvalid),
    .s_axil_awready(awready),
    .s_axil_wdata(wdata),
    .s_axil_wstrb(wstrb),
    .s_axil_wvalid(wvalid),
    .s_axil_wready(wready),
    .s_axil_bresp(bresp),
    .s_axil_bvalid(bvalid),
    .s_axil_bready(bready),
    .s_axil_araddr(araddr),
    .s_axil_arvalid(arvalid),
    .s_axil_arready(arready),
    .s_axil_rdata(rdata),
    .s_axil_rresp(rresp),
    .s_axil_rvalid(rvalid),
    .s_axil_rready(rready),
    .start_pulse,
    .soft_reset_pulse,
    .done_clear_pulse,
    .irq_en,
    .causal_en,
    .q_base,
    .k_base,
    .v_base,
    .o_base,
    .stride_bytes,
    .neg_large,
    .scale,
    .cycles_i,
    .busy_i,
    .done_i,
    .error_i
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic axil_write(input logic [11:0] addr, input logic [31:0] data,
                            input logic [3:0] strb = 4'hf);
    begin
      @(negedge clk);
      awaddr  = addr;
      awvalid = 1'b1;
      wdata   = data;
      wstrb   = strb;
      wvalid  = 1'b1;
      bready  = 1'b1;
      wait (awready && wready);
      @(negedge clk);
      awvalid = 1'b0;
      wvalid  = 1'b0;
      wait (bvalid);
      @(negedge clk);
      bready  = 1'b0;
    end
  endtask

  task automatic axil_read(input logic [11:0] addr, output logic [31:0] data);
    begin
      @(negedge clk);
      araddr  = addr;
      arvalid = 1'b1;
      rready  = 1'b1;
      wait (arready);
      @(negedge clk);
      arvalid = 1'b0;
      wait (rvalid);
      data = rdata;
      @(negedge clk);
      rready  = 1'b0;
    end
  endtask

  task automatic expect_eq(input string name, input logic [31:0] got,
                           input logic [31:0] exp);
    begin
      if (got !== exp) begin
        $error("%s got 0x%08x expected 0x%08x", name, got, exp);
        $fatal(1);
      end
    end
  endtask

  logic [31:0] rd;

  initial begin
    rst_n = 1'b0;
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = 4'h0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b0;
    cycles_i = 32'h1234_5678;
    busy_i = 1'b0;
    done_i = 1'b0;
    error_i = 1'b0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    axil_read(REG_CFG, rd);
    expect_eq("default CFG", rd, 32'h0000_0001);
    axil_read(REG_STRIDE_BYTES, rd);
    expect_eq("default stride", rd, 32'd128);
    axil_read(REG_NEG_LARGE, rd);
    expect_eq("default neg_large", rd, 32'h0000_8000);
    axil_read(REG_SCALE, rd);
    expect_eq("default scale", rd, 32'd32);

    axil_write(REG_Q_BASE_L, 32'h1122_3344);
    axil_write(REG_Q_BASE_H, 32'h5566_7788);
    if (q_base !== 64'h5566_7788_1122_3344) begin
      $fatal(1, "q_base mismatch: 0x%016x", q_base);
    end

    axil_write(REG_CFG, 32'h0000_0000, 4'h0);
    axil_read(REG_CFG, rd);
    expect_eq("WSTRB zero keeps CFG", rd, 32'h0000_0001);

    @(negedge clk);
    awaddr  = REG_CTRL;
    awvalid = 1'b1;
    wdata   = 32'h0000_0005;
    wstrb   = 4'hf;
    wvalid  = 1'b1;
    bready  = 1'b1;
    @(posedge clk);
    #1;
    if (!start_pulse || !irq_en) begin
      $fatal(1, "CTRL did not produce start_pulse and irq_en");
    end
    @(negedge clk);
    awvalid = 1'b0;
    wvalid  = 1'b0;
    @(posedge clk);
    #1;
    bready  = 1'b0;
    if (start_pulse) begin
      $fatal(1, "start_pulse must self clear");
    end

    done_i = 1'b1;
    axil_read(REG_STATUS, rd);
    expect_eq("STATUS done", rd, 32'h0000_0002);
    @(negedge clk);
    awaddr  = REG_STATUS;
    awvalid = 1'b1;
    wdata   = 32'h0000_0002;
    wstrb   = 4'hf;
    wvalid  = 1'b1;
    bready  = 1'b1;
    @(posedge clk);
    #1;
    if (!done_clear_pulse) begin
      $fatal(1, "STATUS W1C did not pulse done_clear");
    end
    @(negedge clk);
    awvalid = 1'b0;
    wvalid  = 1'b0;
    @(posedge clk);
    #1;
    bready  = 1'b0;

    axil_read(REG_CYCLES, rd);
    expect_eq("CYCLES", rd, cycles_i);

    $display("tb_regfile PASS");
    $finish;
  end
endmodule
