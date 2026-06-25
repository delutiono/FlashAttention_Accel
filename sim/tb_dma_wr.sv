`timescale 1ns/1ps

module tb_dma_wr;
  logic clk;
  logic rst_n;

  logic        cmd_valid;
  logic        cmd_ready;
  logic [63:0] cmd_addr;
  logic [8:0]  cmd_beats;
  logic [63:0] in_data;
  logic        in_valid;
  logic        in_ready;
  logic        in_last;
  logic        done;
  logic        error;
  logic [31:0] byte_count;

  logic [63:0] m_axi_awaddr;
  logic [7:0]  m_axi_awlen;
  logic [2:0]  m_axi_awsize;
  logic [1:0]  m_axi_awburst;
  logic        m_axi_awvalid;
  logic        m_axi_awready;
  logic [63:0] m_axi_wdata;
  logic [7:0]  m_axi_wstrb;
  logic        m_axi_wlast;
  logic        m_axi_wvalid;
  logic        m_axi_wready;
  logic [1:0]  m_axi_bresp;
  logic        m_axi_bvalid;
  logic        m_axi_bready;

  logic [63:0] expected_data [0:3];
  integer expected_beats;
  integer observed_beats;
  logic stalled_w;
  logic [63:0] stalled_data;
  logic stalled_last;

  fa_dma_wr dut (
    .clk,
    .rst_n,
    .cmd_valid,
    .cmd_ready,
    .cmd_addr,
    .cmd_beats,
    .in_data,
    .in_valid,
    .in_ready,
    .in_last,
    .done,
    .error,
    .byte_count,
    .m_axi_awaddr,
    .m_axi_awlen,
    .m_axi_awsize,
    .m_axi_awburst,
    .m_axi_awvalid,
    .m_axi_awready,
    .m_axi_wdata,
    .m_axi_wstrb,
    .m_axi_wlast,
    .m_axi_wvalid,
    .m_axi_wready,
    .m_axi_bresp,
    .m_axi_bvalid,
    .m_axi_bready
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
      rst_n         = 1'b0;
      cmd_valid     = 1'b0;
      cmd_addr      = '0;
      cmd_beats     = '0;
      in_data       = '0;
      in_valid      = 1'b0;
      in_last       = 1'b0;
      m_axi_awready = 1'b0;
      m_axi_wready  = 1'b0;
      m_axi_bresp   = 2'b00;
      m_axi_bvalid  = 1'b0;
      expected_beats = 0;
      observed_beats = 0;
      stalled_w = 1'b0;
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

  task automatic accept_aw(
    input int delay_cycles,
    input logic [63:0] exp_addr,
    input logic [7:0] exp_len
  );
    logic [63:0] held_addr;
    logic [7:0] held_len;
    begin
      wait (m_axi_awvalid);
      held_addr = m_axi_awaddr;
      held_len  = m_axi_awlen;
      if (held_addr !== exp_addr || held_len !== exp_len ||
          m_axi_awsize !== 3'd3 || m_axi_awburst !== 2'b01) begin
        fail("AW payload mismatch");
      end
      repeat (delay_cycles) begin
        @(posedge clk);
        #1;
        if (!m_axi_awvalid || m_axi_awaddr !== held_addr ||
            m_axi_awlen !== held_len) begin
          fail("AW payload changed while AWREADY was low");
        end
      end
      @(negedge clk);
      m_axi_awready = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      m_axi_awready = 1'b0;
    end
  endtask

  task automatic send_word(input logic [63:0] data, input logic last);
    begin
      @(negedge clk);
      in_data  = data;
      in_last  = last;
      in_valid = 1'b1;
      do @(posedge clk); while (!in_ready);
      @(negedge clk);
      in_valid = 1'b0;
      in_last  = 1'b0;
    end
  endtask

  task automatic release_one_wbeat(input int stall_cycles);
    begin
      wait (m_axi_wvalid);
      repeat (stall_cycles) @(posedge clk);
      @(negedge clk);
      m_axi_wready = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      m_axi_wready = 1'b0;
    end
  endtask

  task automatic return_b(input logic [1:0] resp, input int delay_cycles);
    begin
      repeat (delay_cycles) begin
        @(posedge clk);
        #1;
        if (m_axi_bready) fail("BREADY asserted before BVALID");
      end
      @(negedge clk);
      m_axi_bresp  = resp;
      m_axi_bvalid = 1'b1;
      do @(posedge clk); while (!m_axi_bready);
      @(negedge clk);
      m_axi_bvalid = 1'b0;
      m_axi_bresp  = 2'b00;
    end
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      stalled_w <= 1'b0;
    end else begin
      if (stalled_w) begin
        if (!m_axi_wvalid || m_axi_wdata !== stalled_data ||
            m_axi_wlast !== stalled_last) begin
          fail("W payload changed while WREADY was low");
        end
      end
      stalled_w <= m_axi_wvalid && !m_axi_wready;
      if (m_axi_wvalid && !m_axi_wready) begin
        stalled_data <= m_axi_wdata;
        stalled_last <= m_axi_wlast;
      end
      if (m_axi_wvalid && m_axi_wready) begin
        if (observed_beats >= expected_beats) fail("too many W beats");
        if (m_axi_wdata !== expected_data[observed_beats] ||
            m_axi_wstrb !== 8'hff ||
            m_axi_wlast !== (observed_beats == expected_beats - 1)) begin
          fail("W payload/WLAST mismatch");
        end
        observed_beats <= observed_beats + 1;
      end
    end
  end

  initial begin
    reset_dut();

    expected_data[0] = 64'h1111;
    expected_data[1] = 64'h2222;
    expected_data[2] = 64'h3333;
    expected_data[3] = 64'h4444;
    expected_beats = 4;
    observed_beats = 0;

    issue_cmd(64'h0000_0002_0000_1000, 9'd4);
    fork
      accept_aw(10, 64'h0000_0002_0000_1000, 8'd3);
      begin
        send_word(expected_data[0], 1'b0);
        release_one_wbeat(3);
        send_word(expected_data[1], 1'b0);
        release_one_wbeat(0);
        send_word(expected_data[2], 1'b0);
        release_one_wbeat(2);
        send_word(expected_data[3], 1'b1);
        release_one_wbeat(1);
      end
    join
    if (observed_beats !== 4 || byte_count !== 32'd32) begin
      fail("write beat count/byte_count mismatch");
    end
    return_b(2'b00, 3);
    #1;
    if (!done || error) fail("normal write completion status mismatch");
    @(posedge clk);
    #1;
    if (done) fail("done must be a one-cycle pulse");

    // BRESP error must propagate to command status.
    expected_data[0] = 64'habcd;
    expected_beats = 1;
    observed_beats = 0;
    issue_cmd(64'h2000, 9'd1);
    fork
      accept_aw(2, 64'h2000, 8'd0);
      begin
        send_word(expected_data[0], 1'b1);
        release_one_wbeat(1);
      end
    join
    return_b(2'b10, 0);
    #1;
    if (!done || !error || byte_count !== 32'd8) begin
      fail("BRESP error was not reported");
    end

    // Stream last disagreement is a command error; AXI WLAST still follows beats.
    expected_data[0] = 64'h5a5a;
    expected_beats = 1;
    observed_beats = 0;
    issue_cmd(64'h3000, 9'd1);
    fork
      accept_aw(0, 64'h3000, 8'd0);
      begin
        send_word(expected_data[0], 1'b0);
        release_one_wbeat(0);
      end
    join
    return_b(2'b00, 0);
    #1;
    if (!done || !error) fail("input stream last mismatch was not reported");

    // The command encoding supports 9 bits, but AXI4 caps one burst at 256 beats.
    issue_cmd(64'h4000, 9'd257);
    #1;
    if (!done || !error || m_axi_awvalid) begin
      fail("write command above 256 beats was not rejected");
    end

    issue_cmd(64'h5000, 9'd256);
    accept_aw(0, 64'h5000, 8'hff);

    $display("tb_dma_wr PASS");
    $finish;
  end

  initial begin
    #20000;
    fail("timeout");
  end
endmodule
