`timescale 1ns/1ps

module tb_compute_core;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned ACC_W = 48;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic signed [ELEM_W-1:0] q_i [D];
  logic signed [ELEM_W-1:0] k_i [D];
  logic valid_o;
  logic signed [ACC_W-1:0] dot_o;

  fa_compute_core #(
    .D(D),
    .ELEM_W(ELEM_W),
    .DOT_ACC_W(ACC_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .q_i,
    .k_i,
    .dot_valid_o(valid_o),
    .dot_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic signed [ACC_W-1:0] ref_dot;
    logic signed [ACC_W-1:0] acc;
    begin
      acc = '0;
      for (int i = 0; i < D; i++) begin
        acc += $signed(q_i[i]) * $signed(k_i[i]);
      end
      return acc;
    end
  endfunction

  initial begin
    rst_n = 1'b0;
    valid_i = 1'b0;
    for (int i = 0; i < D; i++) begin
      q_i[i] = $signed(i - 31) * 16'sd16;
      k_i[i] = $signed(17 - (i % 19)) * 16'sd8;
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    @(negedge clk);
    valid_i = 1'b1;
    @(posedge clk);
    #1;
    if (!valid_o) begin
      $fatal(1, "compute core dot_valid_o not asserted");
    end
    if (dot_o !== ref_dot()) begin
      $fatal(1, "compute core dot_o=%0d expected=%0d", dot_o, ref_dot());
    end

    @(negedge clk);
    valid_i = 1'b0;
    @(posedge clk);
    #1;
    if (valid_o) begin
      $fatal(1, "compute core dot_valid_o did not clear");
    end

    $display("tb_compute_core PASS");
    $finish;
  end
endmodule
