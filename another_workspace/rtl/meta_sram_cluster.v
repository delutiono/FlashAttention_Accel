`timescale 1ns/1ps
`default_nettype none

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

wire rw_rvalid_unused;
wire [127:0] rw_rdata_unused;

sky130_sram_0kbytes_1rw1r_128x16_16_timed_wrapper u_mem (
    .clk(clk),
    .rst_n(rst_n),
    .rw_en(wr_en),
    .rw_write(1'b1),
    .rw_wmask(8'hff),
    .rw_addr(wr_addr),
    .rw_wdata(wr_data),
    .rw_rvalid(rw_rvalid_unused),
    .rw_rdata(rw_rdata_unused),
    .rd_en(rd_en),
    .rd_addr(rd_addr),
    .rd_valid(rd_valid),
    .rd_data(rd_data)
);

endmodule

`default_nettype wire
