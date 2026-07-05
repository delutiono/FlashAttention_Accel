`timescale 1ns/1ps

module tb_axi_mem_model_write_two_bursts;
  localparam int ADDR_W = 64;

  logic clk;
  logic rst_n;

  logic [ADDR_W-1:0] araddr;
  logic [7:0]        arlen;
  logic [2:0]        arsize;
  logic [1:0]        arburst;
  logic              arvalid;
  logic              arready;
  logic [127:0]      rdata;
  logic [1:0]        rresp;
  logic              rlast;
  logic              rvalid;
  logic              rready;

  logic [ADDR_W-1:0] awaddr;
  logic [7:0]        awlen;
  logic [2:0]        awsize;
  logic [1:0]        awburst;
  logic              awvalid;
  logic              awready;
  logic [127:0]      wdata;
  logic [15:0]       wstrb;
  logic              wlast;
  logic              wvalid;
  logic              wready;
  logic [1:0]        bresp;
  logic              bvalid;
  logic              bready;

  int aw_count;
  int w_count;
  int b_count;

  axi_mem_model_128 #(
    .ADDR_W(ADDR_W),
    .MEM_WORDS(20000)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_araddr(araddr),
    .s_axi_arlen(arlen),
    .s_axi_arsize(arsize),
    .s_axi_arburst(arburst),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rlast(rlast),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready),
    .s_axi_awaddr(awaddr),
    .s_axi_awlen(awlen),
    .s_axi_awsize(awsize),
    .s_axi_awburst(awburst),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wlast(wlast),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (!rst_n) begin
      aw_count <= 0;
      w_count <= 0;
      b_count <= 0;
    end else begin
      if (awvalid && awready) aw_count <= aw_count + 1;
      if (wvalid && wready)   w_count <= w_count + 1;
      if (bvalid && bready)   b_count <= b_count + 1;
      if (b_count > aw_count) begin
        $fatal(1, "B response count exceeded accepted AW count");
      end
    end
  end

  task automatic drive_write_burst(input logic [ADDR_W-1:0] base);
    int beat;
    begin
      @(negedge clk);
      awaddr  = base;
      awlen   = 8'd15;
      awsize  = 3'd4;
      awburst = 2'b01;
      awvalid = 1'b1;
      do @(posedge clk); while (!awready);
      @(negedge clk);
      awvalid = 1'b0;

      for (beat = 0; beat < 16; beat = beat + 1) begin
        @(negedge clk);
        wdata  = {64'h0, base[63:4], beat[15:0]};
        wstrb  = 16'hffff;
        wlast  = (beat == 15);
        wvalid = 1'b1;
        do @(posedge clk); while (!wready);
      end
      @(negedge clk);
      wvalid = 1'b0;
      wlast  = 1'b0;

      @(negedge clk);
      bready = 1'b1;
      do @(posedge clk); while (!bvalid);
      if (bresp != 2'b00) begin
        $fatal(1, "Unexpected B response: %0d", bresp);
      end
      @(negedge clk);
      bready = 1'b0;
    end
  endtask

  initial begin
    araddr = '0;
    arlen = '0;
    arsize = 3'd4;
    arburst = 2'b01;
    arvalid = 1'b0;
    rready = 1'b0;
    awaddr = '0;
    awlen = '0;
    awsize = 3'd4;
    awburst = 2'b01;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = '0;
    wlast = 1'b0;
    wvalid = 1'b0;
    bready = 1'b0;
    rst_n = 1'b0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    drive_write_burst(64'h0000_0000_0001_9000);
    drive_write_burst(64'h0000_0000_0001_9100);

    repeat (8) @(posedge clk);
    if (aw_count != 2 || w_count != 32 || b_count != 2) begin
      $fatal(1, "Unexpected handshake counts aw=%0d w=%0d b=%0d",
             aw_count, w_count, b_count);
    end
    $display("PASS: axi_mem_model two write bursts aw=%0d w=%0d b=%0d",
             aw_count, w_count, b_count);
    $finish;
  end
endmodule
