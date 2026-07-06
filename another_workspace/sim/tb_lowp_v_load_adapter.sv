`timescale 1ns/1ps
`default_nettype none

module tb_lowp_v_load_adapter;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic page = 1'b0;
  logic lowp_int8_mode = 1'b1;
  logic [15:0] lowp_v_scale = 16'h8000;
  logic busy;
  logic done;
  logic in_valid = 1'b0;
  logic in_ready;
  logic [127:0] in_data = 128'd0;
  logic in_last = 1'b0;
  logic v_rw_valid;
  logic v_rw_write;
  logic v_rw_pair;
  logic [5:0] v_rw_addr;
  logic [15:0] v_rw_wmask;
  logic [127:0] v_rw_data;
  logic error;

  always #5 clk = ~clk;

  v_load_adapter dut (
    .clk(clk), .rst_n(rst_n), .start(start), .page(page),
    .lowp_int8_mode(lowp_int8_mode), .lowp_v_scale(lowp_v_scale),
    .busy(busy), .done(done), .in_valid(in_valid), .in_ready(in_ready),
    .in_data(in_data), .in_last(in_last),
    .v_rw_valid(v_rw_valid), .v_rw_write(v_rw_write),
    .v_rw_pair(v_rw_pair), .v_rw_addr(v_rw_addr),
    .v_rw_wmask(v_rw_wmask), .v_rw_data(v_rw_data),
    .error(error)
  );

  initial begin
    #2000;
    $display("FAIL: timeout");
    $finish;
  end

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    in_data = {
      8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
      8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'hfe, 8'h02, 8'h01
    };
    in_valid = 1'b1;
    in_last = 1'b0;
    do @(posedge clk); while (!v_rw_valid);
    if (v_rw_data[15:0] !== 16'h0080 ||
        v_rw_data[31:16] !== 16'h0100 ||
        v_rw_data[47:32] !== 16'hff00) begin
      $display("FAIL: scaled V unpack got %h", v_rw_data);
      $finish;
    end
    $display("PASS lowp v_load_adapter scaled unpack");
    $finish;
  end
endmodule

`default_nettype wire
