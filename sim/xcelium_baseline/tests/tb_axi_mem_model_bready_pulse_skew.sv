`timescale 1ns/1ps

module tb_axi_mem_model_bready_pulse_skew;
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

  task automatic drive_aw(input logic [ADDR_W-1:0] base);
    begin
      @(negedge clk);
      awaddr = base;
      awlen = 8'd15;
      awsize = 3'd4;
      awburst = 2'b01;
      awvalid = 1'b1;
      repeat (20) begin
        @(posedge clk);
        if (awready) begin
          @(negedge clk);
          awvalid = 1'b0;
          return;
        end
      end
      $fatal(1, "AW was not accepted for base 0x%016h", base);
    end
  endtask

  task automatic drive_w16(input logic [ADDR_W-1:0] base);
    int beat;
    begin
      for (beat = 0; beat < 16; beat = beat + 1) begin
        @(negedge clk);
        wdata = {64'h0, base[63:4], beat[15:0]};
        wstrb = 16'hffff;
        wlast = (beat == 15);
        wvalid = 1'b1;
        repeat (20) begin
          @(posedge clk);
          if (wready) break;
        end
        if (!wready) begin
          $fatal(1, "W was not accepted for beat %0d", beat);
        end
      end
      @(negedge clk);
      wvalid = 1'b0;
      wlast = 1'b0;
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

    drive_aw(64'h0000_0000_0001_9000);
    drive_w16(64'h0000_0000_0001_9000);

    wait (bvalid === 1'b1);
    #1 bready = 1'b1;
    #1 bready = 1'b0;

    drive_aw(64'h0000_0000_0001_9100);

    if (bvalid) begin
      $fatal(1, "Stale BVALID blocked the next AW after a between-edge BREADY pulse");
    end

    $display("PASS: axi_mem_model clears BVALID after a between-edge BREADY pulse");
    $finish;
  end
endmodule
