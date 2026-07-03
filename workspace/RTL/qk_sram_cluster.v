`timescale 1ns/1ps
`default_nettype none

// 512x32 logical memory built from eight 64x32 macros.
module qk_sram_cluster (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rw_valid,
    input  wire         rw_write,
    input  wire [1:0]   rw_pair,
    input  wire [4:0]   rw_addr,
    input  wire [15:0]  rw_wmask,
    input  wire [127:0] rw_wdata,
    output reg          rw_rvalid,
    output reg  [127:0] rw_rdata,
    input  wire         wide_rd_en,
    input  wire [4:0]   wide_rd_addr,
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

wire [7:0] bank_rw_rvalid;
wire [7:0] bank_rd_valid;
wire [63:0] bank_rw_rdata [0:7];
wire [63:0] bank_rd_data [0:7];
reg  [1:0] rw_pair_d1;
reg  [1:0] rw_pair_d2;
reg        rw_read_d1;
reg        rw_read_d2;

genvar bank_idx;
generate
    for (bank_idx = 0; bank_idx < 8; bank_idx = bank_idx + 1) begin : g_bank
        localparam integer PAIR_INDEX = bank_idx / 2;
        localparam integer PAIR_HALF = bank_idx % 2;
        wire bank_selected;
        wire [63:0] bank_wdata;
        wire [7:0] bank_wmask;

        assign bank_selected = rw_valid && (rw_pair == PAIR_INDEX[1:0]);
        assign bank_wdata = PAIR_HALF ? rw_wdata[127:64] : rw_wdata[63:0];
        assign bank_wmask = PAIR_HALF ? rw_wmask[15:8] : rw_wmask[7:0];

        sky130_sram_0kbytes_1rw1r_64x32_8_wrapper u_bank (
            .clk(clk),
            .rst_n(rst_n),
            .rw_en(bank_selected),
            .rw_write(rw_write),
            .rw_wmask(bank_wmask),
            .rw_addr(rw_addr),
            .rw_wdata(bank_wdata),
            .rw_rvalid(bank_rw_rvalid[bank_idx]),
            .rw_rdata(bank_rw_rdata[bank_idx]),
            .rd_en(wide_rd_en),
            .rd_addr(wide_rd_addr),
            .rd_valid(bank_rd_valid[bank_idx]),
            .rd_data(bank_rd_data[bank_idx])
        );
    end
endgenerate

always @(posedge clk) begin
    if (!rst_n) begin
        rw_pair_d1 <= 2'd0;
        rw_pair_d2 <= 2'd0;
        rw_read_d1 <= 1'b0;
        rw_read_d2 <= 1'b0;
    end else begin
        rw_pair_d1 <= rw_pair;
        rw_pair_d2 <= rw_pair_d1;
        rw_read_d1 <= rw_valid && !rw_write;
        rw_read_d2 <= rw_read_d1;
    end
end

always @(*) begin
    rw_rvalid = 1'b0;
    rw_rdata = 128'd0;
    case (rw_pair_d2)
        2'd0: begin
            rw_rvalid = rw_read_d2 && bank_rw_rvalid[0] && bank_rw_rvalid[1];
            rw_rdata = {bank_rw_rdata[1], bank_rw_rdata[0]};
        end
        2'd1: begin
            rw_rvalid = rw_read_d2 && bank_rw_rvalid[2] && bank_rw_rvalid[3];
            rw_rdata = {bank_rw_rdata[3], bank_rw_rdata[2]};
        end
        2'd2: begin
            rw_rvalid = rw_read_d2 && bank_rw_rvalid[4] && bank_rw_rvalid[5];
            rw_rdata = {bank_rw_rdata[5], bank_rw_rdata[4]};
        end
        default: begin
            rw_rvalid = rw_read_d2 && bank_rw_rvalid[6] && bank_rw_rvalid[7];
            rw_rdata = {bank_rw_rdata[7], bank_rw_rdata[6]};
        end
    endcase
end

assign wide_rd_valid = &bank_rd_valid;
assign wide_rd_data0 = bank_rd_data[0];
assign wide_rd_data1 = bank_rd_data[1];
assign wide_rd_data2 = bank_rd_data[2];
assign wide_rd_data3 = bank_rd_data[3];
assign wide_rd_data4 = bank_rd_data[4];
assign wide_rd_data5 = bank_rd_data[5];
assign wide_rd_data6 = bank_rd_data[6];
assign wide_rd_data7 = bank_rd_data[7];

endmodule

`default_nettype wire
