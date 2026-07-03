`timescale 1ns/1ps
`default_nettype none

module sky130_sram_0kbytes_1rw1r_64x32_8_wrapper (
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

`ifdef SYNTHESIS
wire [32:0] rw_data_lo;
wire [32:0] rw_data_hi;
wire [32:0] rd_data_lo;
wire [32:0] rd_data_hi;

sky130_sram_0kbytes_1rw1r_32x64_8 u_lo (
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

sky130_sram_0kbytes_1rw1r_32x64_8 u_hi (
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
`else
wire [63:0] macro_rd_data;
wire [63:0] macro_rw_data;

sky130_sram_0kbytes_1rw1r_64x32_8 u_mem (
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0(rw_wmask),
    .addr0(rw_addr),
    .din0(rw_wdata),
    .dout0(macro_rw_data),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1(rd_addr),
    .dout1(macro_rd_data)
);
`endif

reg rw_rvalid_d1;
reg rd_valid_d1;

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
`ifdef SYNTHESIS
        rw_rdata <= {rw_data_hi[31:0], rw_data_lo[31:0]};
`else
        rw_rdata <= macro_rw_data;
`endif
        rd_valid_d1 <= rd_en;
        rd_valid <= rd_valid_d1;
`ifdef SYNTHESIS
        rd_data <= {rd_data_hi[31:0], rd_data_lo[31:0]};
`else
        rd_data <= macro_rd_data;
`endif
    end
end

endmodule

`default_nettype wire
