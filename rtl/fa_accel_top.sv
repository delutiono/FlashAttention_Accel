`timescale 1ns/1ps

import fa_pkg::*;

module fa_accel_top #(
  parameter S      = 256,
  parameter D      = 64,
  parameter ELEM_W = 16
) (
  input  logic         clk,
  input  logic         rst_n,

  // AXI4-Lite control
  input  logic [11:0]  s_axil_awaddr,
  input  logic         s_axil_awvalid,
  output logic         s_axil_awready,
  input  logic [31:0]  s_axil_wdata,
  input  logic [3:0]   s_axil_wstrb,
  input  logic         s_axil_wvalid,
  output logic         s_axil_wready,
  output logic [1:0]   s_axil_bresp,
  output logic         s_axil_bvalid,
  input  logic         s_axil_bready,
  input  logic [11:0]  s_axil_araddr,
  input  logic         s_axil_arvalid,
  output logic         s_axil_arready,
  output logic [31:0]  s_axil_rdata,
  output logic [1:0]   s_axil_rresp,
  output logic         s_axil_rvalid,
  input  logic         s_axil_rready,

  // AXI4 Master (tied off for SRAM version)
  output logic [FA_ADDR_W-1:0]     m_axi_araddr,
  output logic [7:0]               m_axi_arlen,
  output logic [2:0]               m_axi_arsize,
  output logic [1:0]               m_axi_arburst,
  output logic                     m_axi_arvalid,
  input  logic                     m_axi_arready,
  input  logic [FA_AXI_DATA_W-1:0] m_axi_rdata,
  input  logic [1:0]               m_axi_rresp,
  input  logic                     m_axi_rlast,
  input  logic                     m_axi_rvalid,
  output logic                     m_axi_rready,

  output logic [FA_ADDR_W-1:0]     m_axi_awaddr,
  output logic [7:0]               m_axi_awlen,
  output logic [2:0]               m_axi_awsize,
  output logic [1:0]               m_axi_awburst,
  output logic                     m_axi_awvalid,
  input  logic                     m_axi_awready,
  output logic [FA_AXI_DATA_W-1:0] m_axi_wdata,
  output logic [FA_AXI_STRB_W-1:0] m_axi_wstrb,
  output logic                     m_axi_wlast,
  output logic                     m_axi_wvalid,
  input  logic                     m_axi_wready,
  input  logic [1:0]               m_axi_bresp,
  input  logic                     m_axi_bvalid,
  output logic                     m_axi_bready,

  output logic                     irq,

  // SRAM-style data ports (for testing without DMA)
  input logic signed [ELEM_W-1:0] q_data_i [S][D],
  input logic signed [ELEM_W-1:0] k_data_i [S][D],
  input logic signed [ELEM_W-1:0] v_data_i [S][D],
  output logic signed [ELEM_W-1:0] o_data_o [S][D],
  output logic signed [S*D*ELEM_W-1:0] o_flat_o
);

  logic        start_pulse;
  logic        soft_reset_pulse;
  logic        irq_en;
  logic        causal_en;
  logic [63:0] q_base;
  logic [63:0] k_base;
  logic [63:0] v_base;
  logic [63:0] o_base;
  logic [31:0] stride_bytes;
  logic [15:0] neg_large;
  logic [15:0] scale;
  logic [31:0] cycles;
  logic        busy;
  logic        done;
  logic        error;

  fa_regfile u_regfile (
    .clk              (clk),
    .rst_n            (rst_n),
    .s_axil_awaddr,   .s_axil_awvalid, .s_axil_awready,
    .s_axil_wdata,    .s_axil_wstrb,   .s_axil_wvalid, .s_axil_wready,
    .s_axil_bresp,    .s_axil_bvalid,  .s_axil_bready,
    .s_axil_araddr,   .s_axil_arvalid, .s_axil_arready,
    .s_axil_rdata,    .s_axil_rresp,   .s_axil_rvalid, .s_axil_rready,
    .start_pulse,     .soft_reset_pulse, .irq_en, .causal_en,
    .q_base, .k_base, .v_base, .o_base,
    .stride_bytes,    .neg_large, .scale,
    .cycles_i (cycles), .busy_i(busy), .done_i(done), .error_i(error)
  );

  fa_scheduler u_scheduler (
    .clk(clk), .rst_n(rst_n),
    .start_i(start_pulse),
    .soft_reset_i(soft_reset_pulse),
    .causal_en_i(causal_en),
    .q_data_i, .k_data_i, .v_data_i,
    .neg_large_i(neg_large),
    .scale_i(scale),
    .busy_o(busy), .done_o(done), .error_o(error), .cycles_o(cycles),
    .o_data_o,
    .o_flat_o
  );

  assign irq = irq_en & done;

  // AXI master tied off
  assign m_axi_araddr  = '0;
  assign m_axi_arlen   = '0;
  assign m_axi_arsize  = 3'd3;
  assign m_axi_arburst = 2'b01;
  assign m_axi_arvalid = 1'b0;
  assign m_axi_rready  = 1'b0;
  assign m_axi_awaddr  = '0;
  assign m_axi_awlen   = '0;
  assign m_axi_awsize  = 3'd3;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awvalid = 1'b0;
  assign m_axi_wdata   = '0;
  assign m_axi_wstrb   = '0;
  assign m_axi_wlast   = 1'b0;
  assign m_axi_wvalid  = 1'b0;
  assign m_axi_bready  = 1'b0;

  // lint helper
  logic _unused;
  assign _unused = q_base[0] ^ k_base[0] ^ v_base[0] ^ o_base[0] ^ stride_bytes[0];

endmodule
