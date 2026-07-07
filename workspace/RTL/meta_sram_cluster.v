`timescale 1ns/1ps
`default_nettype none

// 8x128 meta store built from two 64x64 macros (lo/hi halves).
module meta_sram_cluster (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr_en,
    input  wire [3:0]   wr_addr,
    input  wire [127:0] wr_data,
    input  wire         rd_en,
    input  wire [3:0]   rd_addr,
    output wire         rd_valid,
    output wire [127:0] rd_data
);

wire        rw_rvalid_unused [0:1];
wire [63:0] rw_rdata_unused [0:1];
wire [63:0] bank_rd_data [0:1];
wire [1:0]  bank_rd_valid;
wire [5:0]  addr_6b_l = {2'd0, rd_addr};
wire [5:0]  addr_6b_rw = {2'd0, wr_addr};

sky130_sram_0kbytes_1rw1r_64x64_8_wrapper u_lo (
    .clk(clk), .rst_n(rst_n),
    .rw_en(wr_en), .rw_write(1'b1), .rw_wmask(8'hff),
    .rw_addr(addr_6b_rw), .rw_wdata(wr_data[63:0]),
    .rw_rvalid(rw_rvalid_unused[0]), .rw_rdata(rw_rdata_unused[0]),
    .rd_en(rd_en), .rd_addr(addr_6b_l),
    .rd_valid(bank_rd_valid[0]), .rd_data(bank_rd_data[0])
);

sky130_sram_0kbytes_1rw1r_64x64_8_wrapper u_hi (
    .clk(clk), .rst_n(rst_n),
    .rw_en(wr_en), .rw_write(1'b1), .rw_wmask(8'hff),
    .rw_addr(addr_6b_rw), .rw_wdata(wr_data[127:64]),
    .rw_rvalid(rw_rvalid_unused[1]), .rw_rdata(rw_rdata_unused[1]),
    .rd_en(rd_en), .rd_addr(addr_6b_l),
    .rd_valid(bank_rd_valid[1]), .rd_data(bank_rd_data[1])
);

assign rd_valid = bank_rd_valid[0] && bank_rd_valid[1];
assign rd_data = {bank_rd_data[1], bank_rd_data[0]};

endmodule

`default_nettype wire
