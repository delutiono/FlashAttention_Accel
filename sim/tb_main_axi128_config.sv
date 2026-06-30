`timescale 1ns/1ps

import fa_pkg::*;

module tb_main_axi128_config;
  logic clk;
  logic rst_n;

  logic [11:0] s_axil_awaddr;
  logic        s_axil_awvalid;
  logic        s_axil_awready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_wvalid;
  logic        s_axil_wready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_bvalid;
  logic        s_axil_bready;
  logic [11:0] s_axil_araddr;
  logic        s_axil_arvalid;
  logic        s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready;
  logic [FA_ADDR_W-1:0]     m_axi_araddr;
  logic [7:0]               m_axi_arlen;
  logic [2:0]               m_axi_arsize;
  logic [1:0]               m_axi_arburst;
  logic                     m_axi_arvalid;
  logic                     m_axi_arready;
  logic [FA_AXI_DATA_W-1:0] m_axi_rdata;
  logic [1:0]               m_axi_rresp;
  logic                     m_axi_rlast;
  logic                     m_axi_rvalid;
  logic                     m_axi_rready;
  logic [FA_ADDR_W-1:0]     m_axi_awaddr;
  logic [7:0]               m_axi_awlen;
  logic [2:0]               m_axi_awsize;
  logic [1:0]               m_axi_awburst;
  logic                     m_axi_awvalid;
  logic                     m_axi_awready;
  logic [FA_AXI_DATA_W-1:0] m_axi_wdata;
  logic [FA_AXI_STRB_W-1:0] m_axi_wstrb;
  logic                     m_axi_wlast;
  logic                     m_axi_wvalid;
  logic                     m_axi_wready;
  logic [1:0]               m_axi_bresp;
  logic                     m_axi_bvalid;
  logic                     m_axi_bready;
  logic irq;

  fa_accel_top #(
    .COMPUTE_ROWS(4),
    .KV_TILE_ROWS(2)
  ) dut (
    .clk,
    .rst_n,
    .s_axil_awaddr,
    .s_axil_awvalid,
    .s_axil_awready,
    .s_axil_wdata,
    .s_axil_wstrb,
    .s_axil_wvalid,
    .s_axil_wready,
    .s_axil_bresp,
    .s_axil_bvalid,
    .s_axil_bready,
    .s_axil_araddr,
    .s_axil_arvalid,
    .s_axil_arready,
    .s_axil_rdata,
    .s_axil_rresp,
    .s_axil_rvalid,
    .s_axil_rready,
    .m_axi_araddr,
    .m_axi_arlen,
    .m_axi_arsize,
    .m_axi_arburst,
    .m_axi_arvalid,
    .m_axi_arready,
    .m_axi_rdata,
    .m_axi_rresp,
    .m_axi_rlast,
    .m_axi_rvalid,
    .m_axi_rready,
    .m_axi_awaddr,
    .m_axi_awlen,
    .m_axi_awsize,
    .m_axi_awburst,
    .m_axi_awvalid,
    .m_axi_awready,
    .m_axi_wdata,
    .m_axi_wstrb,
    .m_axi_wlast,
    .m_axi_wvalid,
    .m_axi_wready,
    .m_axi_bresp,
    .m_axi_bvalid,
    .m_axi_bready,
    .irq
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    s_axil_awaddr = '0;
    s_axil_awvalid = 1'b0;
    s_axil_wdata = '0;
    s_axil_wstrb = '0;
    s_axil_wvalid = 1'b0;
    s_axil_bready = 1'b0;
    s_axil_araddr = '0;
    s_axil_arvalid = 1'b0;
    s_axil_rready = 1'b0;
    m_axi_arready = 1'b0;
    m_axi_rdata = '0;
    m_axi_rresp = 2'b00;
    m_axi_rlast = 1'b0;
    m_axi_rvalid = 1'b0;
    m_axi_awready = 1'b0;
    m_axi_wready = 1'b0;
    m_axi_bresp = 2'b00;
    m_axi_bvalid = 1'b0;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    if (FA_AXI_DATA_W != 128) begin
      $fatal(1, "main RTL FA_AXI_DATA_W must be 128 for the baseline path");
    end
    if (FA_AXI_STRB_W != 16) begin
      $fatal(1, "main RTL FA_AXI_STRB_W must be 16 for 128-bit AXI");
    end
    if (dut.TOP_AXI_LANES != 8) begin
      $fatal(1, "main RTL should pack eight int16 lanes per AXI beat");
    end
    if (dut.TOP_ROW_BEATS != 8) begin
      $fatal(1, "main RTL should transfer one D64 row in eight 128-bit beats");
    end
    $display("PASS: main RTL 128-bit AXI config");
    $finish;
  end
endmodule
