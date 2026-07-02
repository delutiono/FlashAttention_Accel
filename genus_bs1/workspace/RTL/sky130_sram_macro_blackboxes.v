`timescale 1ns/1ps
`default_nettype none

module sky130_sram_0kbytes_1rw1r_32x64_8 (
`ifdef USE_POWER_PINS
  inout wire vccd1,
  inout wire vssd1,
`endif
  input  wire                  clk0,
  input  wire                  csb0,
  input  wire                  web0,
  input  wire [3:0]            wmask0,
  input  wire                  spare_wen0,
  input  wire [5:0]            addr0,
  input  wire [32:0]           din0,
  output wire [32:0]           dout0,
  input  wire                  clk1,
  input  wire                  csb1,
  input  wire [5:0]            addr1,
  output wire [32:0]           dout1
);
endmodule

module sky130_sram_0kbytes_1rw1r_48x16_8 (
`ifdef USE_POWER_PINS
  inout wire vccd1,
  inout wire vssd1,
`endif
  input  wire                  clk0,
  input  wire                  csb0,
  input  wire                  web0,
  input  wire [5:0]            wmask0,
  input  wire                  spare_wen0,
  input  wire [3:0]            addr0,
  input  wire [48:0]           din0,
  output wire [48:0]           dout0,
  input  wire                  clk1,
  input  wire                  csb1,
  input  wire [3:0]            addr1,
  output wire [48:0]           dout1
);
endmodule

`default_nettype wire
