`timescale 1ns/1ps
`default_nettype none

// 主线 RTL 的合规 SKY130 SRAM 封装层。
// 这些模块使用 fa_* 命名，作为后续 fa_q_buffer/fa_kv_buffer SRAM 化的项目侧接口；
// 内部只实例化 docs/SKY130_readme.txt 清单中的 SRAM macro。

module fa_sram_1rw1r_64x32_sky130 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rw_en,
    input  wire        rw_write,
    input  wire [7:0]  rw_wmask,
    input  wire [4:0]  rw_addr,
    input  wire [63:0] rw_wdata,
    output reg         rw_rvalid,
    output reg  [63:0] rw_rdata,
    input  wire        rd_en,
    input  wire [4:0]  rd_addr,
    output reg         rd_valid,
    output reg  [63:0] rd_data
);

wire [32:0] rw_data_lo;
wire [32:0] rw_data_hi;
wire [32:0] rd_data_lo;
wire [32:0] rd_data_hi;
reg         rw_rvalid_d1;
reg         rd_valid_d1;

`ifdef SYNTHESIS
sky130_sram_0kbytes_1rw1r_32x64_8 u_lo (
`else
sky130_sram_0kbytes_1rw1r_32x64_8 #(
    .VERBOSE(0)
) u_lo (
`endif
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0(rw_wmask[3:0]),
    .spare_wen0(1'b0),
    .addr0({1'b0, rw_addr}),
    .din0({1'b0, rw_wdata[31:0]}),
    .dout0(rw_data_lo),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1({1'b0, rd_addr}),
    .dout1(rd_data_lo)
);

`ifdef SYNTHESIS
sky130_sram_0kbytes_1rw1r_32x64_8 u_hi (
`else
sky130_sram_0kbytes_1rw1r_32x64_8 #(
    .VERBOSE(0)
) u_hi (
`endif
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0(rw_wmask[7:4]),
    .spare_wen0(1'b0),
    .addr0({1'b0, rw_addr}),
    .din0({1'b0, rw_wdata[63:32]}),
    .dout0(rw_data_hi),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1({1'b0, rd_addr}),
    .dout1(rd_data_hi)
);

always @(posedge clk) begin
    if (!rst_n) begin
        rw_rvalid_d1 <= 1'b0;
        rw_rvalid <= 1'b0;
        rw_rdata <= 64'd0;
        rd_valid_d1 <= 1'b0;
        rd_valid <= 1'b0;
        rd_data <= 64'd0;
    end else begin
        rw_rvalid_d1 <= rw_en && !rw_write;
        rw_rvalid <= rw_rvalid_d1;
        rw_rdata <= {rw_data_hi[31:0], rw_data_lo[31:0]};
        rd_valid_d1 <= rd_en;
        rd_valid <= rd_valid_d1;
        rd_data <= {rd_data_hi[31:0], rd_data_lo[31:0]};
    end
end

endmodule

module fa_sram_1rw1r_64x64_sky130 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rw_en,
    input  wire        rw_write,
    input  wire [7:0]  rw_wmask,
    input  wire [5:0]  rw_addr,
    input  wire [63:0] rw_wdata,
    output reg         rw_rvalid,
    output reg  [63:0] rw_rdata,
    input  wire        rd_en,
    input  wire [5:0]  rd_addr,
    output reg         rd_valid,
    output reg  [63:0] rd_data
);

wire [32:0] rw_data_lo;
wire [32:0] rw_data_hi;
wire [32:0] rd_data_lo;
wire [32:0] rd_data_hi;
reg         rw_rvalid_d1;
reg         rd_valid_d1;

`ifdef SYNTHESIS
sky130_sram_0kbytes_1rw1r_32x64_8 u_lo (
`else
sky130_sram_0kbytes_1rw1r_32x64_8 #(
    .VERBOSE(0)
) u_lo (
`endif
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0(rw_wmask[3:0]),
    .spare_wen0(1'b0),
    .addr0(rw_addr),
    .din0({1'b0, rw_wdata[31:0]}),
    .dout0(rw_data_lo),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1(rd_addr),
    .dout1(rd_data_lo)
);

`ifdef SYNTHESIS
sky130_sram_0kbytes_1rw1r_32x64_8 u_hi (
`else
sky130_sram_0kbytes_1rw1r_32x64_8 #(
    .VERBOSE(0)
) u_hi (
`endif
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0(rw_wmask[7:4]),
    .spare_wen0(1'b0),
    .addr0(rw_addr),
    .din0({1'b0, rw_wdata[63:32]}),
    .dout0(rw_data_hi),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1(rd_addr),
    .dout1(rd_data_hi)
);

always @(posedge clk) begin
    if (!rst_n) begin
        rw_rvalid_d1 <= 1'b0;
        rw_rvalid <= 1'b0;
        rw_rdata <= 64'd0;
        rd_valid_d1 <= 1'b0;
        rd_valid <= 1'b0;
        rd_data <= 64'd0;
    end else begin
        rw_rvalid_d1 <= rw_en && !rw_write;
        rw_rvalid <= rw_rvalid_d1;
        rw_rdata <= {rw_data_hi[31:0], rw_data_lo[31:0]};
        rd_valid_d1 <= rd_en;
        rd_valid <= rd_valid_d1;
        rd_data <= {rd_data_hi[31:0], rd_data_lo[31:0]};
    end
end

endmodule

module fa_sram_1rw1r_128x16_sky130 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rw_en,
    input  wire         rw_write,
    input  wire [7:0]   rw_wmask,
    input  wire [3:0]   rw_addr,
    input  wire [127:0] rw_wdata,
    output reg          rw_rvalid,
    output reg  [127:0] rw_rdata,
    input  wire         rd_en,
    input  wire [3:0]   rd_addr,
    output reg          rd_valid,
    output reg  [127:0] rd_data
);

wire [48:0] rw_data_0;
wire [48:0] rw_data_1;
wire [48:0] rw_data_2;
wire [48:0] rd_data_0;
wire [48:0] rd_data_1;
wire [48:0] rd_data_2;
reg         rw_rvalid_d1;
reg         rd_valid_d1;

`ifdef SYNTHESIS
sky130_sram_0kbytes_1rw1r_48x16_8 u_lane_0_2 (
`else
sky130_sram_0kbytes_1rw1r_48x16_8 #(
    .VERBOSE(0)
) u_lane_0_2 (
`endif
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0({rw_wmask[2], rw_wmask[2], rw_wmask[1], rw_wmask[1], rw_wmask[0], rw_wmask[0]}),
    .spare_wen0(1'b0),
    .addr0(rw_addr),
    .din0({1'b0, rw_wdata[47:0]}),
    .dout0(rw_data_0),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1(rd_addr),
    .dout1(rd_data_0)
);

`ifdef SYNTHESIS
sky130_sram_0kbytes_1rw1r_48x16_8 u_lane_3_5 (
`else
sky130_sram_0kbytes_1rw1r_48x16_8 #(
    .VERBOSE(0)
) u_lane_3_5 (
`endif
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0({rw_wmask[5], rw_wmask[5], rw_wmask[4], rw_wmask[4], rw_wmask[3], rw_wmask[3]}),
    .spare_wen0(1'b0),
    .addr0(rw_addr),
    .din0({1'b0, rw_wdata[95:48]}),
    .dout0(rw_data_1),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1(rd_addr),
    .dout1(rd_data_1)
);

`ifdef SYNTHESIS
sky130_sram_0kbytes_1rw1r_48x16_8 u_lane_6_7 (
`else
sky130_sram_0kbytes_1rw1r_48x16_8 #(
    .VERBOSE(0)
) u_lane_6_7 (
`endif
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0({2'b00, rw_wmask[7], rw_wmask[7], rw_wmask[6], rw_wmask[6]}),
    .spare_wen0(1'b0),
    .addr0(rw_addr),
    .din0({1'b0, 16'd0, rw_wdata[127:96]}),
    .dout0(rw_data_2),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1(rd_addr),
    .dout1(rd_data_2)
);

always @(posedge clk) begin
    if (!rst_n) begin
        rw_rvalid_d1 <= 1'b0;
        rw_rvalid <= 1'b0;
        rw_rdata <= 128'd0;
        rd_valid_d1 <= 1'b0;
        rd_valid <= 1'b0;
        rd_data <= 128'd0;
    end else begin
        rw_rvalid_d1 <= rw_en && !rw_write;
        rw_rvalid <= rw_rvalid_d1;
        rw_rdata <= {rw_data_2[31:0], rw_data_1[47:0], rw_data_0[47:0]};
        rd_valid_d1 <= rd_en;
        rd_valid <= rd_valid_d1;
        rd_data <= {rd_data_2[31:0], rd_data_1[47:0], rd_data_0[47:0]};
    end
end

endmodule

`default_nettype wire
