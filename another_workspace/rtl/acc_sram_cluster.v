`timescale 1ns/1ps
`default_nettype none

// 16x128x12 ACC half store built from twelve 128x16 PDK-compatible wrappers.
// Address encoding is {context[2:0], half}; one access covers 32 signed lanes.
module acc_sram_cluster (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr_en,
    input  wire [3:0]   wr_addr,
    input  wire [127:0] wr_data0,
    input  wire [127:0] wr_data1,
    input  wire [127:0] wr_data2,
    input  wire [127:0] wr_data3,
    input  wire [127:0] wr_data4,
    input  wire [127:0] wr_data5,
    input  wire [127:0] wr_data6,
    input  wire [127:0] wr_data7,
    input  wire [127:0] wr_data8,
    input  wire [127:0] wr_data9,
    input  wire [127:0] wr_data10,
    input  wire [127:0] wr_data11,
    input  wire         rd_en,
    input  wire [3:0]   rd_addr,
    output wire         rd_valid,
    output wire [127:0] rd_data0,
    output wire [127:0] rd_data1,
    output wire [127:0] rd_data2,
    output wire [127:0] rd_data3,
    output wire [127:0] rd_data4,
    output wire [127:0] rd_data5,
    output wire [127:0] rd_data6,
    output wire [127:0] rd_data7,
    output wire [127:0] rd_data8,
    output wire [127:0] rd_data9,
    output wire [127:0] rd_data10,
    output wire [127:0] rd_data11
);

wire [11:0] bank_rd_valid;
wire [127:0] bank_rd_data [0:11];
wire [127:0] bank_wr_data [0:11];
wire [11:0] bank_rw_rvalid_unused;
wire [127:0] bank_rw_rdata_unused [0:11];

assign bank_wr_data[0] = wr_data0;
assign bank_wr_data[1] = wr_data1;
assign bank_wr_data[2] = wr_data2;
assign bank_wr_data[3] = wr_data3;
assign bank_wr_data[4] = wr_data4;
assign bank_wr_data[5] = wr_data5;
assign bank_wr_data[6] = wr_data6;
assign bank_wr_data[7] = wr_data7;
assign bank_wr_data[8] = wr_data8;
assign bank_wr_data[9] = wr_data9;
assign bank_wr_data[10] = wr_data10;
assign bank_wr_data[11] = wr_data11;

genvar bank_idx;
generate
    for (bank_idx = 0; bank_idx < 12; bank_idx = bank_idx + 1) begin : g_bank
        sky130_sram_0kbytes_1rw1r_128x16_16_timed_wrapper u_bank (
            .clk(clk),
            .rst_n(rst_n),
            .rw_en(wr_en),
            .rw_write(1'b1),
            .rw_wmask(8'hff),
            .rw_addr(wr_addr),
            .rw_wdata(bank_wr_data[bank_idx]),
            .rw_rvalid(bank_rw_rvalid_unused[bank_idx]),
            .rw_rdata(bank_rw_rdata_unused[bank_idx]),
            .rd_en(rd_en),
            .rd_addr(rd_addr),
            .rd_valid(bank_rd_valid[bank_idx]),
            .rd_data(bank_rd_data[bank_idx])
        );
    end
endgenerate

assign rd_valid = &bank_rd_valid;
assign rd_data0 = bank_rd_data[0];
assign rd_data1 = bank_rd_data[1];
assign rd_data2 = bank_rd_data[2];
assign rd_data3 = bank_rd_data[3];
assign rd_data4 = bank_rd_data[4];
assign rd_data5 = bank_rd_data[5];
assign rd_data6 = bank_rd_data[6];
assign rd_data7 = bank_rd_data[7];
assign rd_data8 = bank_rd_data[8];
assign rd_data9 = bank_rd_data[9];
assign rd_data10 = bank_rd_data[10];
assign rd_data11 = bank_rd_data[11];

endmodule

`default_nettype wire
