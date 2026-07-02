`timescale 1ns/1ps

module tb_score_pipe;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned ACC_W = 48;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic [7:0] q_index_i;
  logic [7:0] k_index_i;
  logic signed [ELEM_W-1:0] q_i [D];
  logic signed [ELEM_W-1:0] k_i [D];
  logic valid_o;
  logic [7:0] q_index_o;
  logic [7:0] k_index_o;
  logic signed [ACC_W-1:0] score_o;

  fa_score_pipe #(
    .D(D),
    .ELEM_W(ELEM_W),
    .SCORE_W(ACC_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .q_index_i,
    .k_index_i,
    .q_i,
    .k_i,
    .valid_o,
    .q_index_o,
    .k_index_o,
    .score_o
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

  function automatic logic signed [ACC_W-1:0] ref_scaled_score;
    begin
      return ref_dot() >>> 3;
    end
  endfunction

  initial begin
    rst_n = 1'b0;
    valid_i = 1'b0;
    q_index_i = 8'd0;
    k_index_i = 8'd0;
    for (int i = 0; i < D; i++) begin
      q_i[i] = 16'sd0;
      k_i[i] = 16'sd0;
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    for (int i = 0; i < D; i++) begin
      q_i[i] = 16'sd3;
      k_i[i] = (i == 9) ? -16'sd7 : 16'sd0;
    end
    q_index_i = 8'd12;
    k_index_i = 8'd34;
    valid_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    valid_i = 1'b0;
    wait (valid_o);
    #1;
    if (q_index_o !== 8'd12 || k_index_o !== 8'd34) begin
      $fatal(1, "index mismatch q=%0d k=%0d", q_index_o, k_index_o);
    end
    if (score_o !== ref_scaled_score()) begin
      $fatal(1, "score_o=%0d expected_scaled=%0d raw=%0d",
             score_o, ref_scaled_score(), ref_dot());
    end

    @(negedge clk);
    q_index_i = 8'd55;
    k_index_i = 8'd66;
    @(posedge clk);
    #1;
    if (valid_o) begin
      $fatal(1, "valid_o did not clear");
    end
    if (score_o !== '0) begin
      $fatal(1, "score_o did not clear");
    end

    $display("tb_score_pipe PASS");
    $finish;
  end
endmodule
