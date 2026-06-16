`timescale 1ns/1ps

module tb_dot_pe;
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

  fa_dot_pe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .ACC_W(ACC_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .q_i,
    .k_i,
    .valid_o,
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

  task automatic clear_vecs;
    begin
      for (int i = 0; i < D; i++) begin
        q_i[i] = '0;
        k_i[i] = '0;
      end
    end
  endtask

  task automatic run_case(input string name);
    logic signed [ACC_W-1:0] expected;
    begin
      expected = ref_dot();
      @(negedge clk);
      valid_i = 1'b1;
      @(posedge clk);
      #1;
      if (!valid_o) begin
        $fatal(1, "%s: valid_o not asserted", name);
      end
      if (dot_o !== expected) begin
        $fatal(1, "%s: dot_o=%0d expected=%0d", name, dot_o, expected);
      end
      @(negedge clk);
      valid_i = 1'b0;
      @(posedge clk);
      #1;
      if (valid_o) begin
        $fatal(1, "%s: valid_o did not self clear", name);
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    valid_i = 1'b0;
    clear_vecs();

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    clear_vecs();
    run_case("zero");

    clear_vecs();
    q_i[3] = 16'sd256;   // 1.0 in Q8.8
    k_i[3] = -16'sd512;  // -2.0 in Q8.8
    run_case("one_hot");

    clear_vecs();
    for (int i = 0; i < D; i++) begin
      q_i[i] = $signed((i % 7) - 3) * 16'sd128;
      k_i[i] = $signed((i % 5) - 2) * 16'sd64;
    end
    run_case("signed_mixed");

    $display("tb_dot_pe PASS");
    $finish;
  end
endmodule
