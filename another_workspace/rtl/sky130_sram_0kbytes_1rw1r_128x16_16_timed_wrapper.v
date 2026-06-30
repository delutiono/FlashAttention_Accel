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

wire [127:0] macro_rw_data;
wire [127:0] macro_rd_data;
reg          rw_rvalid_d1;
reg          rd_valid_d1;

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
        rw_rdata <= macro_rw_data;
        rd_valid_d1 <= rd_en;
        rd_valid <= rd_valid_d1;
        rd_data <= macro_rd_data;
    end
end

endmodule

`default_nettype wire
