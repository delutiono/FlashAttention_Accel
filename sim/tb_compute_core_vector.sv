`timescale 1ns/1ps

module tb_compute_core_vector;
  localparam int unsigned S = 256;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned ACC_W = 48;
  localparam int unsigned Q_ROW = 0;
  localparam int unsigned K_ROW = 0;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic signed [ELEM_W-1:0] q_i [D];
  logic signed [ELEM_W-1:0] k_i [D];
  logic valid_o;
  logic signed [ACC_W-1:0] dot_o;

  logic [ELEM_W-1:0] q_mem [S * D];
  logic [ELEM_W-1:0] k_mem [S * D];
  logic signed [ACC_W-1:0] observed_dot;

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
    $readmemh("test_vectors/test_000_Q.hex", q_mem);
    $readmemh("test_vectors/test_000_K.hex", k_mem);

    rst_n = 1'b0;
    valid_i = 1'b0;
    for (int i = 0; i < D; i++) begin
      q_i[i] = $signed(q_mem[Q_ROW * D + i]);
      k_i[i] = $signed(k_mem[K_ROW * D + i]);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    @(negedge clk);
    valid_i = 1'b1;
    @(posedge clk);
    #1;
    if (!valid_o) begin
      $fatal(1, "vector dot_valid_o not asserted");
    end
    if (dot_o !== ref_dot()) begin
      $fatal(1, "vector dot_o=%0d expected=%0d", dot_o, ref_dot());
    end
    observed_dot = dot_o;

    @(negedge clk);
    valid_i = 1'b0;
    @(posedge clk);
    #1;
    if (valid_o) begin
      $fatal(1, "vector dot_valid_o did not clear");
    end

    $display("tb_compute_core_vector PASS q_row=%0d k_row=%0d dot=%0d",
             Q_ROW, K_ROW, observed_dot);
    $finish;
  end
endmodule
