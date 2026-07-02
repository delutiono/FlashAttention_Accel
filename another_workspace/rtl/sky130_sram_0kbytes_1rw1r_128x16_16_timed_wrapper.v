`timescale 1ns/1ps
`default_nettype none

module sky130_sram_0kbytes_1rw1r_128x16_16_timed_wrapper (
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

`ifdef SYNTHESIS
wire [48:0] rw_data_0;
wire [48:0] rw_data_1;
wire [48:0] rw_data_2;
wire [48:0] rd_data_0;
wire [48:0] rd_data_1;
wire [48:0] rd_data_2;

// Lane 0: bits [47:0], wmask[2:0] -> 48-bit macro (each wmask bit covers 2 bytes)
sky130_sram_0kbytes_1rw1r_48x16_8 u_lane_0 (
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0({rw_wmask[2], rw_wmask[2], rw_wmask[1], rw_wmask[1], rw_wmask[0], rw_wmask[0]}),
    .spare_wen0(1'b0),
    .addr0({2'd0, rw_addr}),
    .din0({1'b0, rw_wdata[47:0]}),
    .dout0(rw_data_0),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1({2'd0, rd_addr}),
    .dout1(rd_data_0)
);

// Lane 1: bits [95:48], wmask[5:3]
sky130_sram_0kbytes_1rw1r_48x16_8 u_lane_1 (
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0({rw_wmask[5], rw_wmask[5], rw_wmask[4], rw_wmask[4], rw_wmask[3], rw_wmask[3]}),
    .spare_wen0(1'b0),
    .addr0({2'd0, rw_addr}),
    .din0({1'b0, rw_wdata[95:48]}),
    .dout0(rw_data_1),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1({2'd0, rd_addr}),
    .dout1(rd_data_1)
);

// Lane 2: bits [127:96] (32 bits), wmask[7:6]
sky130_sram_0kbytes_1rw1r_48x16_8 u_lane_2 (
`ifdef USE_POWER_PINS
    .vccd1(),
    .vssd1(),
`endif
    .clk0(clk),
    .csb0(~rw_en),
    .web0(~rw_write),
    .wmask0({2'b00, rw_wmask[7], rw_wmask[7], rw_wmask[6], rw_wmask[6]}),
    .spare_wen0(1'b0),
    .addr0({2'd0, rw_addr}),
    .din0({1'b0, 16'd0, rw_wdata[127:96]}),
    .dout0(rw_data_2),
    .clk1(clk),
    .csb1(~rd_en),
    .addr1({2'd0, rd_addr}),
    .dout1(rd_data_2)
);
`else
wire [127:0] macro_rw_data;
wire [127:0] macro_rd_data;

sky130_sram_0kbytes_1rw1r_128x16_16 u_mem (
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

reg          rw_rvalid_d1;
reg          rd_valid_d1;

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
`ifdef SYNTHESIS
        rw_rdata <= {rw_data_2[31:0], rw_data_1[47:0], rw_data_0[47:0]};
`else
        rw_rdata <= macro_rw_data;
`endif
        rd_valid_d1 <= rd_en;
        rd_valid <= rd_valid_d1;
`ifdef SYNTHESIS
        rd_data <= {rd_data_2[31:0], rd_data_1[47:0], rd_data_0[47:0]};
`else
        rd_data <= macro_rd_data;
`endif
    end
end

endmodule

`default_nettype wire
