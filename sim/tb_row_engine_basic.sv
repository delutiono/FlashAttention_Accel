`timescale 1ns/1ps

module tb_row_engine_basic;
  localparam int unsigned D = 64;
  localparam int unsigned ELEM_W = 16;
  localparam int unsigned OUT_W = 16;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic row_start_i;
  logic last_i;
  logic [7:0] q_index_i;
  logic [7:0] k_index_i;
  logic signed [ELEM_W-1:0] q_i [D];
  logic signed [ELEM_W-1:0] k_i [D];
  logic signed [ELEM_W-1:0] v_i [D];
  logic ready_o;
  logic busy_o;
  logic valid_o;
  logic div_zero_o;
  logic signed [OUT_W-1:0] o_q88_o [D];

  fa_row_engine #(
    .D(D),
    .ELEM_W(ELEM_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .row_start_i,
    .last_i,
    .q_index_i,
    .k_index_i,
    .q_i,
    .k_i,
    .v_i,
    .ready_o,
    .busy_o,
    .valid_o,
    .div_zero_o,
    .o_q88_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic clear_inputs;
    begin
      valid_i = 1'b0;
      row_start_i = 1'b0;
      last_i = 1'b0;
      q_index_i = 8'h0;
      k_index_i = 8'h0;
      for (int lane = 0; lane < D; lane++) begin
        q_i[lane] = '0;
        k_i[lane] = '0;
        v_i[lane] = '0;
      end
    end
  endtask

  task automatic drive_key(
    input logic row_start,
    input logic last,
    input logic [7:0] k_index,
    input logic signed [ELEM_W-1:0] k_lane0,
    input logic signed [ELEM_W-1:0] v_lane0
  );
    begin
      @(negedge clk);
      if (ready_o !== 1'b1) begin
        $fatal(1, "row engine was not ready before k%0d", k_index);
      end

      clear_inputs();
      valid_i = 1'b1;
      row_start_i = row_start;
      last_i = last;
      q_index_i = 8'd1;
      k_index_i = k_index;
      q_i[0] = 16'sh0100;
      k_i[0] = k_lane0;
      v_i[0] = v_lane0;

      @(negedge clk);
      clear_inputs();
    end
  endtask

  task automatic wait_output;
    begin
      for (int guard = 0; guard < 64; guard++) begin
        @(posedge clk);
        #1;
        if (valid_o === 1'b1) begin
          return;
        end
      end

      $fatal(1, "row engine output timeout");
    end
  endtask

  initial begin
    rst_n = 1'b0;
    clear_inputs();

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    if (ready_o !== 1'b1) begin
      $fatal(1, "ready_o not asserted after reset release");
    end

    drive_key(1'b1, 1'b0, 8'd0, 16'sh0000, 16'sh0100);
    drive_key(1'b0, 1'b1, 8'd1, 16'she000, 16'sh0200);

    wait_output();

    if (div_zero_o !== 1'b0) begin
      $fatal(1, "unexpected divide-by-zero");
    end

    if (o_q88_o[0] !== 16'sh0105) begin
      $fatal(1, "lane0 o_q88=0x%04h expected=0x0105", o_q88_o[0]);
    end

    for (int lane = 1; lane < D; lane++) begin
      if (o_q88_o[lane] !== '0) begin
        $fatal(1, "lane%0d o_q88=0x%04h expected=0x0000",
               lane, o_q88_o[lane]);
      end
    end

    $display("tb_row_engine_basic PASS");
    $finish;
  end
endmodule
