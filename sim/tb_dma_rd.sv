`timescale 1ns/1ps

module tb_dma_rd;
  logic clk;
  logic rst_n;

  logic        cmd_valid;
  logic        cmd_ready;
  logic [63:0] cmd_addr;
  logic [8:0]  cmd_beats;

  logic [63:0] out_data;
  logic        out_valid;
  logic        out_ready;
  logic        out_last;
  logic        done;
  logic        error;
  logic [31:0] byte_count;

  logic [63:0] m_axi_araddr;
  logic [7:0]  m_axi_arlen;
  logic [2:0]  m_axi_arsize;
  logic [1:0]  m_axi_arburst;
  logic        m_axi_arvalid;
  logic        m_axi_arready;
  logic [63:0] m_axi_rdata;
  logic [1:0]  m_axi_rresp;
  logic        m_axi_rlast;
  logic        m_axi_rvalid;
  logic        m_axi_rready;

  fa_dma_rd dut (
    .clk,
    .rst_n,
    .cmd_valid,
    .cmd_ready,
    .cmd_addr,
    .cmd_beats,
    .out_data,
    .out_valid,
    .out_ready,
    .out_last,
    .done,
    .error,
    .byte_count,
    .m_axi_araddr,
    .m_axi_arlen,
    .m_axi_arsize,
    .m_axi_arburst,
    .m_axi_arvalid,
    .m_axi_arready,
    .m_axi_rdata,
    .m_axi_rresp,
    .m_axi_rlast,
    .m_axi_rvalid,
    .m_axi_rready
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic fail(input string message);
    begin
      $error("%s", message);
      $fatal(1);
    end
  endtask

  task automatic reset_dut;
    begin
      rst_n        = 1'b0;
      cmd_valid    = 1'b0;
      cmd_addr     = '0;
      cmd_beats    = '0;
      out_ready    = 1'b0;
      m_axi_arready = 1'b0;
      m_axi_rdata  = '0;
      m_axi_rresp  = 2'b00;
      m_axi_rlast  = 1'b0;
      m_axi_rvalid = 1'b0;
      repeat (4) @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(negedge clk);
      if (!cmd_ready) fail("cmd_ready must assert after reset");
    end
  endtask

  task automatic issue_cmd(input logic [63:0] addr, input logic [8:0] beats);
    begin
      @(negedge clk);
      cmd_addr  = addr;
      cmd_beats = beats;
      cmd_valid = 1'b1;
      do @(posedge clk); while (!cmd_ready);
      @(negedge clk);
      cmd_valid = 1'b0;
    end
  endtask

  task automatic accept_ar(
    input int delay_cycles,
    input logic [63:0] exp_addr,
    input logic [7:0] exp_len
  );
    logic [63:0] held_addr;
    logic [7:0] held_len;
    begin
      wait (m_axi_arvalid);
      held_addr = m_axi_araddr;
      held_len  = m_axi_arlen;
      if (held_addr !== exp_addr || held_len !== exp_len ||
          m_axi_arsize !== 3'd3 || m_axi_arburst !== 2'b01) begin
        fail("AR payload mismatch");
      end
      repeat (delay_cycles) begin
        @(posedge clk);
        #1;
        if (!m_axi_arvalid || m_axi_araddr !== held_addr ||
            m_axi_arlen !== held_len) begin
          fail("AR payload changed while ARREADY was low");
        end
      end
      @(negedge clk);
      m_axi_arready = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      m_axi_arready = 1'b0;
    end
  endtask

  task automatic push_rbeat(
    input logic [63:0] data,
    input logic [1:0] resp,
    input logic last,
    input int hole_cycles
  );
    begin
      repeat (hole_cycles) @(posedge clk);
      @(negedge clk);
      m_axi_rdata  = data;
      m_axi_rresp  = resp;
      m_axi_rlast  = last;
      m_axi_rvalid = 1'b1;
      do @(posedge clk); while (!m_axi_rready);
      @(negedge clk);
      m_axi_rvalid = 1'b0;
      m_axi_rlast  = 1'b0;
      m_axi_rresp  = 2'b00;
    end
  endtask

  task automatic take_output(
    input logic [63:0] exp_data,
    input logic exp_last
  );
    begin
      out_ready = 1'b1;
      do @(posedge clk); while (!out_valid);
      #1;
      if (out_data !== exp_data || out_last !== exp_last) begin
        fail("read stream payload/last mismatch");
      end
      @(negedge clk);
      out_ready = 1'b0;
    end
  endtask

  initial begin
    reset_dut();

    // Normal burst: delayed ARREADY, RVALID holes, and output backpressure.
    issue_cmd(64'h0000_0001_2345_6000, 9'd4);
    accept_ar(3, 64'h0000_0001_2345_6000, 8'd3);

    push_rbeat(64'h1000, 2'b00, 1'b0, 2);
    take_output(64'h1000, 1'b0);

    out_ready = 1'b0;
    push_rbeat(64'h2000, 2'b00, 1'b0, 1);
    repeat (3) begin
      @(posedge clk);
      #1;
      if (!out_valid || out_data !== 64'h2000 || out_last) begin
        fail("read output changed while downstream stalled");
      end
    end
    take_output(64'h2000, 1'b0);

    push_rbeat(64'h3000, 2'b00, 1'b0, 3);
    take_output(64'h3000, 1'b0);
    push_rbeat(64'h4000, 2'b00, 1'b1, 1);
    take_output(64'h4000, 1'b1);
    #1;
    if (!done || error || byte_count !== 32'd32) begin
      fail("normal read completion status mismatch");
    end
    @(posedge clk);
    #1;
    if (done) fail("done must be a one-cycle pulse");

    // RRESP error is accumulated through completion.
    issue_cmd(64'h8000, 9'd1);
    accept_ar(0, 64'h8000, 8'd0);
    push_rbeat(64'hdead_beef, 2'b10, 1'b1, 0);
    take_output(64'hdead_beef, 1'b1);
    #1;
    if (!done || !error || byte_count !== 32'd8) begin
      fail("RRESP error was not reported");
    end

    // Both early and missing RLAST must be detected; stream last follows cmd_beats.
    issue_cmd(64'h9000, 9'd2);
    accept_ar(1, 64'h9000, 8'd1);
    push_rbeat(64'h51, 2'b00, 1'b1, 0);
    take_output(64'h51, 1'b0);
    push_rbeat(64'h52, 2'b00, 1'b0, 0);
    take_output(64'h52, 1'b1);
    #1;
    if (!done || !error || byte_count !== 32'd16) begin
      fail("RLAST protocol error was not reported");
    end

    // The command encoding supports 9 bits, but AXI4 caps one burst at 256 beats.
    issue_cmd(64'ha000, 9'd257);
    #1;
    if (!done || !error || m_axi_arvalid) begin
      fail("read command above 256 beats was not rejected");
    end

    issue_cmd(64'hb000, 9'd256);
    accept_ar(0, 64'hb000, 8'hff);

    $display("tb_dma_rd PASS");
    $finish;
  end

  initial begin
    #20000;
    fail("timeout");
  end
endmodule
