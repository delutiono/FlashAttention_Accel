`timescale 1ns/1ps

// Behavioral model: 16 entries x 128 bits, 1RW + 1R port, 1-cycle sync read

module sky130_sram_0kbytes_1rw1r_128x16_16 (
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
    clk0,
    csb0,
    web0,
    wmask0,
    addr0,
    din0,
    dout0,
    clk1,
    csb1,
    addr1,
    dout1
);

`ifdef USE_POWER_PINS
    inout vccd1;
    inout vssd1;
`endif

  input         clk0;
  input         csb0;
  input         web0;
  input  [7:0]  wmask0;
  input  [3:0]  addr0;
  input  [127:0] din0;
  output reg [127:0] dout0;
  input         clk1;
  input         csb1;
  input  [3:0]  addr1;
  output reg [127:0] dout1;

  reg [127:0] mem [0:15];

  // wmask0 is 8-bit for 128-bit data: each bit covers 16 bits
  always @(posedge clk0) begin
    if (!csb0 && !web0) begin
      if (wmask0[0]) mem[addr0][ 15:  0] <= din0[ 15:  0];
      if (wmask0[1]) mem[addr0][ 31: 16] <= din0[ 31: 16];
      if (wmask0[2]) mem[addr0][ 47: 32] <= din0[ 47: 32];
      if (wmask0[3]) mem[addr0][ 63: 48] <= din0[ 63: 48];
      if (wmask0[4]) mem[addr0][ 79: 64] <= din0[ 79: 64];
      if (wmask0[5]) mem[addr0][ 95: 80] <= din0[ 95: 80];
      if (wmask0[6]) mem[addr0][111: 96] <= din0[111: 96];
      if (wmask0[7]) mem[addr0][127:112] <= din0[127:112];
    end
    if (!csb0)
      dout0 <= mem[addr0];
  end

  always @(posedge clk1) begin
    if (!csb1)
      dout1 <= mem[addr1];
  end

endmodule
