`timescale 1ns/1ps
`default_nettype none

// 256x64 logical memory built from four 64x64 macros.
module v_sram_cluster (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rw_valid,
    input  wire         rw_write,
    input  wire         rw_pair,
    input  wire [5:0]   rw_addr,
    input  wire [15:0]  rw_wmask,
    input  wire [127:0] rw_wdata,
    output reg          rw_rvalid,
    output reg  [127:0] rw_rdata,
    input  wire         wide_rd_en,
    input  wire [5:0]   wide_rd_addr,
    output wire         wide_rd_valid,
    output wire [63:0]  wide_rd_data0,
    output wire [63:0]  wide_rd_data1,
    output wire [63:0]  wide_rd_data2,
    output wire [63:0]  wide_rd_data3,
    output wire [63:0]  wide_rd_data4,
    output wire [63:0]  wide_rd_data5,
    output wire [63:0]  wide_rd_data6,
    output wire [63:0]  wide_rd_data7
);

wire [3:0] bank_rw_rvalid_p0;
wire [3:0] bank_rw_rvalid_p1;
wire [3:0] bank_rd_valid_p0;
wire [3:0] bank_rd_valid_p1;
wire [63:0] bank_rw_rdata_p0 [0:3];
wire [63:0] bank_rw_rdata_p1 [0:3];
wire [63:0] bank_rd_data_p0 [0:3];
wire [63:0] bank_rd_data_p1 [0:3];
reg rw_pair_d1;
reg rw_pair_d2;
reg rw_read_d1;
reg rw_read_d2;
reg rw_page_d1;
reg rw_page_d2;
reg wide_page_d1;
reg wide_page_d2;

genvar bank_idx;
generate
    for (bank_idx = 0; bank_idx < 4; bank_idx = bank_idx + 1) begin : g_bank
        localparam integer PAIR_INDEX = bank_idx / 2;
        localparam integer PAIR_HALF = bank_idx % 2;
        wire bank_selected_p0;
        wire bank_selected_p1;
        wire [63:0] bank_wdata;
        wire [7:0] bank_wmask;

        assign bank_selected_p0 = rw_valid && !rw_addr[5] && (rw_pair == PAIR_INDEX[0]);
        assign bank_selected_p1 = rw_valid && rw_addr[5] && (rw_pair == PAIR_INDEX[0]);
        assign bank_wdata = PAIR_HALF ? rw_wdata[127:64] : rw_wdata[63:0];
        assign bank_wmask = PAIR_HALF ? rw_wmask[15:8] : rw_wmask[7:0];

        sky130_sram_0kbytes_1rw1r_64x64_8_wrapper u_bank_p0 (
            .clk(clk),
            .rst_n(rst_n),
            .rw_en((wide_rd_en && !wide_rd_addr[5]) || bank_selected_p0),
            .rw_write((wide_rd_en && !wide_rd_addr[5]) ? 1'b0 : rw_write),
            .rw_wmask(bank_wmask),
            .rw_addr((wide_rd_en && !wide_rd_addr[5]) ? ({1'b0, wide_rd_addr[4:0]} + 6'd1) : {1'b0, rw_addr[4:0]}),
            .rw_wdata(bank_wdata),
            .rw_rvalid(bank_rw_rvalid_p0[bank_idx]),
            .rw_rdata(bank_rw_rdata_p0[bank_idx]),
            .rd_en(wide_rd_en && !wide_rd_addr[5]),
            .rd_addr({1'b0, wide_rd_addr[4:0]}),
            .rd_valid(bank_rd_valid_p0[bank_idx]),
            .rd_data(bank_rd_data_p0[bank_idx])
        );

        sky130_sram_0kbytes_1rw1r_64x64_8_wrapper u_bank_p1 (
            .clk(clk),
            .rst_n(rst_n),
            .rw_en((wide_rd_en && wide_rd_addr[5]) || bank_selected_p1),
            .rw_write((wide_rd_en && wide_rd_addr[5]) ? 1'b0 : rw_write),
            .rw_wmask(bank_wmask),
            .rw_addr((wide_rd_en && wide_rd_addr[5]) ? ({1'b0, wide_rd_addr[4:0]} + 6'd1) : {1'b0, rw_addr[4:0]}),
            .rw_wdata(bank_wdata),
            .rw_rvalid(bank_rw_rvalid_p1[bank_idx]),
            .rw_rdata(bank_rw_rdata_p1[bank_idx]),
            .rd_en(wide_rd_en && wide_rd_addr[5]),
            .rd_addr({1'b0, wide_rd_addr[4:0]}),
            .rd_valid(bank_rd_valid_p1[bank_idx]),
            .rd_data(bank_rd_data_p1[bank_idx])
        );
    end
endgenerate

always @(posedge clk) begin
    if (!rst_n) begin
        rw_pair_d1 <= 1'b0;
        rw_pair_d2 <= 1'b0;
        rw_read_d1 <= 1'b0;
        rw_read_d2 <= 1'b0;
        rw_page_d1 <= 1'b0;
        rw_page_d2 <= 1'b0;
        wide_page_d1 <= 1'b0;
        wide_page_d2 <= 1'b0;
    end else begin
        rw_pair_d1 <= rw_pair;
        rw_pair_d2 <= rw_pair_d1;
        rw_read_d1 <= rw_valid && !rw_write;
        rw_read_d2 <= rw_read_d1;
        rw_page_d1 <= rw_addr[5];
        rw_page_d2 <= rw_page_d1;
        wide_page_d1 <= wide_rd_addr[5];
        wide_page_d2 <= wide_page_d1;
    end
end

always @(*) begin
    if (!rw_pair_d2 && !rw_page_d2) begin
        rw_rvalid = rw_read_d2 && bank_rw_rvalid_p0[0] && bank_rw_rvalid_p0[1];
        rw_rdata = {bank_rw_rdata_p0[1], bank_rw_rdata_p0[0]};
    end else if (!rw_pair_d2) begin
        rw_rvalid = rw_read_d2 && bank_rw_rvalid_p1[0] && bank_rw_rvalid_p1[1];
        rw_rdata = {bank_rw_rdata_p1[1], bank_rw_rdata_p1[0]};
    end else if (!rw_page_d2) begin
        rw_rvalid = rw_read_d2 && bank_rw_rvalid_p0[2] && bank_rw_rvalid_p0[3];
        rw_rdata = {bank_rw_rdata_p0[3], bank_rw_rdata_p0[2]};
    end else begin
        rw_rvalid = rw_read_d2 && bank_rw_rvalid_p1[2] && bank_rw_rvalid_p1[3];
        rw_rdata = {bank_rw_rdata_p1[3], bank_rw_rdata_p1[2]};
    end
end

assign wide_rd_valid = wide_page_d2 ?
                       ((&bank_rd_valid_p1) && (&bank_rw_rvalid_p1)) :
                       ((&bank_rd_valid_p0) && (&bank_rw_rvalid_p0));
assign wide_rd_data0 = wide_page_d2 ? bank_rd_data_p1[0] : bank_rd_data_p0[0];
assign wide_rd_data1 = wide_page_d2 ? bank_rd_data_p1[1] : bank_rd_data_p0[1];
assign wide_rd_data2 = wide_page_d2 ? bank_rd_data_p1[2] : bank_rd_data_p0[2];
assign wide_rd_data3 = wide_page_d2 ? bank_rd_data_p1[3] : bank_rd_data_p0[3];
assign wide_rd_data4 = wide_page_d2 ? bank_rw_rdata_p1[0] : bank_rw_rdata_p0[0];
assign wide_rd_data5 = wide_page_d2 ? bank_rw_rdata_p1[1] : bank_rw_rdata_p0[1];
assign wide_rd_data6 = wide_page_d2 ? bank_rw_rdata_p1[2] : bank_rw_rdata_p0[2];
assign wide_rd_data7 = wide_page_d2 ? bank_rw_rdata_p1[3] : bank_rw_rdata_p0[3];

`ifndef SYNTHESIS
always @(posedge clk) begin
    if (rst_n && wide_rd_en && rw_valid && (wide_rd_addr[5] == rw_addr[5])) begin
        $display("ERROR: v_sram_cluster same-page load/update port collision");
        $finish;
    end
end
`endif

endmodule

`default_nettype wire
