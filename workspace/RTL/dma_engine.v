`timescale 1ns/1ps
`default_nettype none

module dma_engine #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 128,
    parameter TAG_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  cmd_valid,
    output wire                  cmd_ready,
    input  wire [1:0]            cmd_kind,
    input  wire                  cmd_page,
    input  wire [ADDR_WIDTH-1:0] cmd_base_addr,
    input  wire [15:0]           cmd_bytes,
    input  wire [TAG_WIDTH-1:0]  cmd_tag,
    output wire                  rd_valid,
    input  wire                  rd_ready,
    output wire [1:0]            rd_kind,
    output wire                  rd_page,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_last,
    output wire [TAG_WIDTH-1:0]  rd_tag,
    input  wire                  wr_valid,
    output wire                  wr_ready,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire [(DATA_WIDTH/8)-1:0] wr_strb,
    input  wire                  wr_last,
    output wire                  done_valid,
    output wire [1:0]            done_kind,
    output wire                  done_page,
    output wire [TAG_WIDTH-1:0]  done_tag,
    output wire                  done_error,
    output wire [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready,
    output wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_awvalid,
    input  wire                  m_axi_awready,
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [(DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready
);

localparam [1:0] KIND_Q_LOAD = 2'd0;
localparam [1:0] KIND_K_LOAD = 2'd1;
localparam [1:0] KIND_V_LOAD = 2'd2;
localparam [1:0] KIND_O_STORE = 2'd3;

wire cmd_is_write = (cmd_kind == KIND_O_STORE);
wire rd_cmd_ready;
wire wr_cmd_ready;
wire rd_done_valid;
wire [1:0] rd_done_kind;
wire rd_done_page;
wire [TAG_WIDTH-1:0] rd_done_tag;
wire rd_error;
wire wr_done_valid;
wire [TAG_WIDTH-1:0] wr_done_tag;
wire wr_error;

assign cmd_ready = cmd_is_write ? wr_cmd_ready : rd_cmd_ready;
assign done_valid = rd_done_valid || wr_done_valid;
assign done_kind = wr_done_valid ? KIND_O_STORE : rd_done_kind;
assign done_page = wr_done_valid ? 1'b0 : rd_done_page;
assign done_tag = wr_done_valid ? wr_done_tag : rd_done_tag;
assign done_error = (rd_done_valid && rd_error) || (wr_done_valid && wr_error);

dma_read_master #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .TAG_WIDTH(TAG_WIDTH)
) u_read (
    .clk(clk), .rst_n(rst_n),
    .cmd_valid(cmd_valid && !cmd_is_write), .cmd_ready(rd_cmd_ready),
    .cmd_base_addr(cmd_base_addr), .cmd_bytes(cmd_bytes),
    .cmd_kind(cmd_kind), .cmd_page(cmd_page), .cmd_tag(cmd_tag),
    .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_data(rd_data),
    .rd_last(rd_last), .rd_kind(rd_kind), .rd_page(rd_page), .rd_tag(rd_tag),
    .done_valid(rd_done_valid), .done_kind(rd_done_kind),
    .done_page(rd_done_page), .done_tag(rd_done_tag), .error(rd_error)
);

dma_write_master #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .TAG_WIDTH(TAG_WIDTH)
) u_write (
    .clk(clk), .rst_n(rst_n),
    .cmd_valid(cmd_valid && cmd_is_write), .cmd_ready(wr_cmd_ready),
    .cmd_base_addr(cmd_base_addr), .cmd_bytes(cmd_bytes), .cmd_tag(cmd_tag),
    .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_data(wr_data),
    .wr_strb(wr_strb), .wr_last(wr_last),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .done_valid(wr_done_valid), .done_tag(wr_done_tag), .error(wr_error)
);

endmodule

`default_nettype wire
