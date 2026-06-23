`timescale 1ns/1ps

`include "fa_defines.vh"

module tb_scheduler_gate;

  localparam S      = 4;
  localparam D      = 64;
  localparam BK     = 2;
  localparam ELEM_W = 16;

  logic clk, rst_n;
  logic start_i, soft_reset_i, causal_en_i;
  logic signed [S*D*ELEM_W-1:0] q_data_i;
  logic signed [S*D*ELEM_W-1:0] k_data_i;
  logic signed [S*D*ELEM_W-1:0] v_data_i;
  logic [15:0]  neg_large_i;
  logic [15:0]  scale_i;
  logic busy_o, done_o, error_o;
  logic [31:0] cycles_o;
  logic signed [S*D*ELEM_W-1:0] o_data_o;
  logic signed [S*D*ELEM_W-1:0] o_flat_o;

  logic signed [ELEM_W-1:0] q_data_u [S][D];
  logic signed [ELEM_W-1:0] k_data_u [S][D];
  logic signed [ELEM_W-1:0] v_data_u [S][D];

  always_comb begin
    for (int r = 0; r < S; r++)
      for (int c = 0; c < D; c++) begin
        q_data_i[(r*D + c)*ELEM_W +: ELEM_W] = q_data_u[r][c];
        k_data_i[(r*D + c)*ELEM_W +: ELEM_W] = k_data_u[r][c];
        v_data_i[(r*D + c)*ELEM_W +: ELEM_W] = v_data_u[r][c];
      end
  end

`ifdef GATE_SIM
  fa_scheduler #(.S(S), .BK(BK)) u_dut (
`else
  fa_scheduler #(.S(S), .D(D), .ELEM_W(ELEM_W), .BK(BK),
                 .DOT_LANES(32), .V_LANES(16), .SCORE_W(24),
                 .EXP_W(16), .L_W(32), .ACC_W(48)) u_dut (
`endif
    .clk(clk), .rst_n(rst_n),
    .start_i, .soft_reset_i, .causal_en_i,
    .q_data_i, .k_data_i, .v_data_i,
    .neg_large_i, .scale_i,
    .busy_o, .done_o, .error_o,
    .cycles_o, .o_data_o, .o_flat_o
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    for (int r = 0; r < S; r++)
      for (int c = 0; c < D; c++) begin
        q_data_u[r][c] = 16'h0100;
        k_data_u[r][c] = 16'h0100;
        v_data_u[r][c] = 16'h0080;
      end
  end

  initial begin
    rst_n = 0;
    start_i = 0;
    soft_reset_i = 0;
    causal_en_i = 1;
    neg_large_i = 16'h8000;
    scale_i = 16'h0100;

    #20 rst_n = 1;
    repeat (5) @(posedge clk);

    $display("[%0t] Starting scheduler gate-level test (S=%0d, BK=%0d)...", $time, S, BK);
    start_i = 1;
    @(posedge clk);
    start_i = 0;

    while (!done_o) @(posedge clk);

    $display("[%0t] DONE!  Cycles: %0d  error=%0d", $time, cycles_o, error_o);
    $display("  o_flat_o[0..3] = %h %h %h %h",
      o_flat_o[0*ELEM_W +: ELEM_W], o_flat_o[1*ELEM_W +: ELEM_W],
      o_flat_o[2*ELEM_W +: ELEM_W], o_flat_o[3*ELEM_W +: ELEM_W]);

    $display("[%0t] Test complete.", $time);
    $finish;
  end

  initial begin
    #10000000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
