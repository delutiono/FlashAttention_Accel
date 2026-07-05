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

    // SRAM SDF annotation scaffold generated from timing/fa_top_mapped.sdf.
    specify
        (clk0 => dout0[0]) = (0:0:0, 0:0:0);
        (clk0 => dout0[1]) = (0:0:0, 0:0:0);
        (clk0 => dout0[2]) = (0:0:0, 0:0:0);
        (clk0 => dout0[3]) = (0:0:0, 0:0:0);
        (clk0 => dout0[4]) = (0:0:0, 0:0:0);
        (clk0 => dout0[5]) = (0:0:0, 0:0:0);
        (clk0 => dout0[6]) = (0:0:0, 0:0:0);
        (clk0 => dout0[7]) = (0:0:0, 0:0:0);
        (clk0 => dout0[8]) = (0:0:0, 0:0:0);
        (clk0 => dout0[9]) = (0:0:0, 0:0:0);
        (clk0 => dout0[10]) = (0:0:0, 0:0:0);
        (clk0 => dout0[11]) = (0:0:0, 0:0:0);
        (clk0 => dout0[12]) = (0:0:0, 0:0:0);
        (clk0 => dout0[13]) = (0:0:0, 0:0:0);
        (clk0 => dout0[14]) = (0:0:0, 0:0:0);
        (clk0 => dout0[15]) = (0:0:0, 0:0:0);
        (clk0 => dout0[16]) = (0:0:0, 0:0:0);
        (clk0 => dout0[17]) = (0:0:0, 0:0:0);
        (clk0 => dout0[18]) = (0:0:0, 0:0:0);
        (clk0 => dout0[19]) = (0:0:0, 0:0:0);
        (clk0 => dout0[20]) = (0:0:0, 0:0:0);
        (clk0 => dout0[21]) = (0:0:0, 0:0:0);
        (clk0 => dout0[22]) = (0:0:0, 0:0:0);
        (clk0 => dout0[23]) = (0:0:0, 0:0:0);
        (clk0 => dout0[24]) = (0:0:0, 0:0:0);
        (clk0 => dout0[25]) = (0:0:0, 0:0:0);
        (clk0 => dout0[26]) = (0:0:0, 0:0:0);
        (clk0 => dout0[27]) = (0:0:0, 0:0:0);
        (clk0 => dout0[28]) = (0:0:0, 0:0:0);
        (clk0 => dout0[29]) = (0:0:0, 0:0:0);
        (clk0 => dout0[30]) = (0:0:0, 0:0:0);
        (clk0 => dout0[31]) = (0:0:0, 0:0:0);
        (clk0 => dout0[32]) = (0:0:0, 0:0:0);
        (clk0 => dout0[33]) = (0:0:0, 0:0:0);
        (clk0 => dout0[34]) = (0:0:0, 0:0:0);
        (clk0 => dout0[35]) = (0:0:0, 0:0:0);
        (clk0 => dout0[36]) = (0:0:0, 0:0:0);
        (clk0 => dout0[37]) = (0:0:0, 0:0:0);
        (clk0 => dout0[38]) = (0:0:0, 0:0:0);
        (clk0 => dout0[39]) = (0:0:0, 0:0:0);
        (clk0 => dout0[40]) = (0:0:0, 0:0:0);
        (clk0 => dout0[41]) = (0:0:0, 0:0:0);
        (clk0 => dout0[42]) = (0:0:0, 0:0:0);
        (clk0 => dout0[43]) = (0:0:0, 0:0:0);
        (clk0 => dout0[44]) = (0:0:0, 0:0:0);
        (clk0 => dout0[45]) = (0:0:0, 0:0:0);
        (clk0 => dout0[46]) = (0:0:0, 0:0:0);
        (clk0 => dout0[47]) = (0:0:0, 0:0:0);
        (clk0 => dout0[48]) = (0:0:0, 0:0:0);
        (clk0 => dout0[49]) = (0:0:0, 0:0:0);
        (clk0 => dout0[50]) = (0:0:0, 0:0:0);
        (clk0 => dout0[51]) = (0:0:0, 0:0:0);
        (clk0 => dout0[52]) = (0:0:0, 0:0:0);
        (clk0 => dout0[53]) = (0:0:0, 0:0:0);
        (clk0 => dout0[54]) = (0:0:0, 0:0:0);
        (clk0 => dout0[55]) = (0:0:0, 0:0:0);
        (clk0 => dout0[56]) = (0:0:0, 0:0:0);
        (clk0 => dout0[57]) = (0:0:0, 0:0:0);
        (clk0 => dout0[58]) = (0:0:0, 0:0:0);
        (clk0 => dout0[59]) = (0:0:0, 0:0:0);
        (clk0 => dout0[60]) = (0:0:0, 0:0:0);
        (clk0 => dout0[61]) = (0:0:0, 0:0:0);
        (clk0 => dout0[62]) = (0:0:0, 0:0:0);
        (clk0 => dout0[63]) = (0:0:0, 0:0:0);
        (clk1 => dout1[0]) = (0:0:0, 0:0:0);
        (clk1 => dout1[1]) = (0:0:0, 0:0:0);
        (clk1 => dout1[2]) = (0:0:0, 0:0:0);
        (clk1 => dout1[3]) = (0:0:0, 0:0:0);
        (clk1 => dout1[4]) = (0:0:0, 0:0:0);
        (clk1 => dout1[5]) = (0:0:0, 0:0:0);
        (clk1 => dout1[6]) = (0:0:0, 0:0:0);
        (clk1 => dout1[7]) = (0:0:0, 0:0:0);
        (clk1 => dout1[8]) = (0:0:0, 0:0:0);
        (clk1 => dout1[9]) = (0:0:0, 0:0:0);
        (clk1 => dout1[10]) = (0:0:0, 0:0:0);
        (clk1 => dout1[11]) = (0:0:0, 0:0:0);
        (clk1 => dout1[12]) = (0:0:0, 0:0:0);
        (clk1 => dout1[13]) = (0:0:0, 0:0:0);
        (clk1 => dout1[14]) = (0:0:0, 0:0:0);
        (clk1 => dout1[15]) = (0:0:0, 0:0:0);
        (clk1 => dout1[16]) = (0:0:0, 0:0:0);
        (clk1 => dout1[17]) = (0:0:0, 0:0:0);
        (clk1 => dout1[18]) = (0:0:0, 0:0:0);
        (clk1 => dout1[19]) = (0:0:0, 0:0:0);
        (clk1 => dout1[20]) = (0:0:0, 0:0:0);
        (clk1 => dout1[21]) = (0:0:0, 0:0:0);
        (clk1 => dout1[22]) = (0:0:0, 0:0:0);
        (clk1 => dout1[23]) = (0:0:0, 0:0:0);
        (clk1 => dout1[24]) = (0:0:0, 0:0:0);
        (clk1 => dout1[25]) = (0:0:0, 0:0:0);
        (clk1 => dout1[26]) = (0:0:0, 0:0:0);
        (clk1 => dout1[27]) = (0:0:0, 0:0:0);
        (clk1 => dout1[28]) = (0:0:0, 0:0:0);
        (clk1 => dout1[29]) = (0:0:0, 0:0:0);
        (clk1 => dout1[30]) = (0:0:0, 0:0:0);
        (clk1 => dout1[31]) = (0:0:0, 0:0:0);
        (clk1 => dout1[32]) = (0:0:0, 0:0:0);
        (clk1 => dout1[33]) = (0:0:0, 0:0:0);
        (clk1 => dout1[34]) = (0:0:0, 0:0:0);
        (clk1 => dout1[35]) = (0:0:0, 0:0:0);
        (clk1 => dout1[36]) = (0:0:0, 0:0:0);
        (clk1 => dout1[37]) = (0:0:0, 0:0:0);
        (clk1 => dout1[38]) = (0:0:0, 0:0:0);
        (clk1 => dout1[39]) = (0:0:0, 0:0:0);
        (clk1 => dout1[40]) = (0:0:0, 0:0:0);
        (clk1 => dout1[41]) = (0:0:0, 0:0:0);
        (clk1 => dout1[42]) = (0:0:0, 0:0:0);
        (clk1 => dout1[43]) = (0:0:0, 0:0:0);
        (clk1 => dout1[44]) = (0:0:0, 0:0:0);
        (clk1 => dout1[45]) = (0:0:0, 0:0:0);
        (clk1 => dout1[46]) = (0:0:0, 0:0:0);
        (clk1 => dout1[47]) = (0:0:0, 0:0:0);
        (clk1 => dout1[48]) = (0:0:0, 0:0:0);
        (clk1 => dout1[49]) = (0:0:0, 0:0:0);
        (clk1 => dout1[50]) = (0:0:0, 0:0:0);
        (clk1 => dout1[51]) = (0:0:0, 0:0:0);
        (clk1 => dout1[52]) = (0:0:0, 0:0:0);
        (clk1 => dout1[53]) = (0:0:0, 0:0:0);
        (clk1 => dout1[54]) = (0:0:0, 0:0:0);
        (clk1 => dout1[55]) = (0:0:0, 0:0:0);
        (clk1 => dout1[56]) = (0:0:0, 0:0:0);
        (clk1 => dout1[57]) = (0:0:0, 0:0:0);
        (clk1 => dout1[58]) = (0:0:0, 0:0:0);
        (clk1 => dout1[59]) = (0:0:0, 0:0:0);
        (clk1 => dout1[60]) = (0:0:0, 0:0:0);
        (clk1 => dout1[61]) = (0:0:0, 0:0:0);
        (clk1 => dout1[62]) = (0:0:0, 0:0:0);
        (clk1 => dout1[63]) = (0:0:0, 0:0:0);
    endspecify
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
