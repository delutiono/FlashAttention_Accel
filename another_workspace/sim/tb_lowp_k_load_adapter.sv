`timescale 1ns/1ps
`default_nettype none

module tb_lowp_k_load_adapter;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic page = 1'b0;
  logic busy;
  logic done;
  logic in_valid = 1'b0;
  logic in_ready;
  logic [127:0] in_data = 128'd0;
  logic in_last = 1'b0;
  logic lowp_int8_mode = 1'b1;
  logic k_rw_valid;
  logic k_rw_write;
  logic [1:0] k_rw_pair;
  logic [4:0] k_rw_addr;
  logic [15:0] k_rw_wmask;
  logic [127:0] k_rw_data;
  logic error;

  always #5 clk = ~clk;

  initial begin
    #2000;
    $display("FAIL: timeout");
    $finish;
  end

  k_load_adapter dut (
    .clk(clk), .rst_n(rst_n), .start(start), .page(page),
    .lowp_int8_mode(lowp_int8_mode),
    .busy(busy), .done(done),
    .in_valid(in_valid), .in_ready(in_ready),
    .in_data(in_data), .in_last(in_last),
    .k_rw_valid(k_rw_valid), .k_rw_write(k_rw_write),
    .k_rw_pair(k_rw_pair), .k_rw_addr(k_rw_addr),
    .k_rw_wmask(k_rw_wmask), .k_rw_data(k_rw_data),
    .error(error)
  );

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    in_data = {
      8'h80, 8'h7f, 8'hff, 8'h01, 8'h40, 8'hc0, 8'h02, 8'hfe,
      8'h10, 8'hf0, 8'h20, 8'he0, 8'h30, 8'hd0, 8'h00, 8'h01
    };
    in_valid = 1'b1;
    in_last = 1'b0;
    do @(posedge clk); while (!k_rw_valid);
    if (k_rw_data !== {16'h1000,16'hf000,16'h2000,16'he000,16'h3000,16'hd000,16'h0000,16'h0100}) begin
      $display("FAIL: unpacked word0 got %h", k_rw_data);
      $finish;
    end
    if (k_rw_pair !== 2'd0 || k_rw_addr !== 5'd0) begin
      $display("FAIL: first unpack address pair=%0d addr=%0d", k_rw_pair, k_rw_addr);
      $finish;
    end
    do @(posedge clk); while (!k_rw_valid);
    if (k_rw_data !== {16'h8000,16'h7f00,16'hff00,16'h0100,16'h4000,16'hc000,16'h0200,16'hfe00}) begin
      $display("FAIL: unpacked word1 got %h", k_rw_data);
      $finish;
    end
    if (k_rw_pair !== 2'd1 || k_rw_addr !== 5'd0) begin
      $display("FAIL: second unpack address pair=%0d addr=%0d", k_rw_pair, k_rw_addr);
      $finish;
    end
    $display("PASS lowp k_load_adapter unpack");
    $finish;
  end
endmodule

`default_nettype wire
