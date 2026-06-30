`timescale 1ns/1ps

// Behavioral model: 64 entries x 64 bits, 1RW + 1R port, 1-cycle sync read

module sky130_sram_0kbytes_1rw1r_64x64_8 (
    input         clk0,
    input         csb0,
    input         web0,
    input  [7:0]  wmask0,
    input  [5:0]  addr0,
    input  [63:0] din0,
    output reg [63:0] dout0,
    input         clk1,
    input         csb1,
    input  [5:0]  addr1,
    output reg [63:0] dout1
);

  reg [63:0] mem [0:63];

  always @(posedge clk0) begin
    if (!csb0 && !web0) begin
      if (wmask0[0]) mem[addr0][ 7: 0] <= din0[ 7: 0];
      if (wmask0[1]) mem[addr0][15: 8] <= din0[15: 8];
      if (wmask0[2]) mem[addr0][23:16] <= din0[23:16];
      if (wmask0[3]) mem[addr0][31:24] <= din0[31:24];
      if (wmask0[4]) mem[addr0][39:32] <= din0[39:32];
      if (wmask0[5]) mem[addr0][47:40] <= din0[47:40];
      if (wmask0[6]) mem[addr0][55:48] <= din0[55:48];
      if (wmask0[7]) mem[addr0][63:56] <= din0[63:56];
    end
    if (!csb0)
      dout0 <= mem[addr0];
  end

  always @(posedge clk1) begin
    if (!csb1)
      dout1 <= mem[addr1];
  end

endmodule
