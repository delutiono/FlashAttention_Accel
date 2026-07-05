`timescale 1ns/1ps
`default_nettype none

module sky130_sram_0kbytes_1rw1r_64x32_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [7:0]  wmask0,
    input  wire [4:0]  addr0,
    input  wire [63:0] din0,
    output reg  [63:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [4:0]  addr1,
    output reg  [63:0] dout1
);
  reg [63:0] mem [0:31];
  integer byte_idx;
  integer init_idx;

  initial begin
    for (init_idx = 0; init_idx < 32; init_idx = init_idx + 1) begin
      mem[init_idx] = 64'd0;
    end
    dout0 = 64'd0;
    dout1 = 64'd0;
  end

  always @(posedge clk0) begin
    if (!csb0) begin
      dout0 <= mem[addr0];
      if (!web0) begin
        for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
          if (wmask0[byte_idx]) begin
            mem[addr0][byte_idx*8 +: 8] <= din0[byte_idx*8 +: 8];
          end
        end
      end
    end
  end

  always @(posedge clk1) begin
    if (!csb1) begin
      dout1 <= mem[addr1];
    end
  end
endmodule

module sky130_sram_0kbytes_1rw1r_64x64_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [7:0]  wmask0,
    input  wire [5:0]  addr0,
    input  wire [63:0] din0,
    output reg  [63:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [5:0]  addr1,
    output reg  [63:0] dout1
);
  reg [63:0] mem [0:63];
  integer byte_idx;
  integer init_idx;

  initial begin
    for (init_idx = 0; init_idx < 64; init_idx = init_idx + 1) begin
      mem[init_idx] = 64'd0;
    end
    dout0 = 64'd0;
    dout1 = 64'd0;
  end

  always @(posedge clk0) begin
    if (!csb0) begin
      dout0 <= mem[addr0];
      if (!web0) begin
        for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
          if (wmask0[byte_idx]) begin
            mem[addr0][byte_idx*8 +: 8] <= din0[byte_idx*8 +: 8];
          end
        end
      end
    end
  end

  always @(posedge clk1) begin
    if (!csb1) begin
      dout1 <= mem[addr1];
    end
  end
endmodule

module sky130_sram_0kbytes_1rw1r_128x16_16 (
`ifdef USE_POWER_PINS
    inout  wire        vccd1,
    inout  wire        vssd1,
`endif
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [7:0]  wmask0,
    input  wire [3:0]  addr0,
    input  wire [127:0] din0,
    output reg  [127:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [3:0]  addr1,
    output reg  [127:0] dout1
);
  reg [127:0] mem [0:15];
  integer lane_idx;
  integer init_idx;

  initial begin
    for (init_idx = 0; init_idx < 16; init_idx = init_idx + 1) begin
      mem[init_idx] = 128'd0;
    end
    dout0 = 128'd0;
    dout1 = 128'd0;
  end

  always @(posedge clk0) begin
    if (!csb0) begin
      dout0 <= mem[addr0];
      if (!web0) begin
        for (lane_idx = 0; lane_idx < 8; lane_idx = lane_idx + 1) begin
          if (wmask0[lane_idx]) begin
            mem[addr0][lane_idx*16 +: 16] <= din0[lane_idx*16 +: 16];
          end
        end
      end
    end
  end

  always @(posedge clk1) begin
    if (!csb1) begin
      dout1 <= mem[addr1];
    end
  end
endmodule

`default_nettype wire
