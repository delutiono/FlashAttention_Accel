`timescale 1ns/1ps

import fa_pkg::*;

module tb_top_dma_smoke;
  localparam logic [63:0] Q_BASE = 64'h0000_0000_0000_1000;
  localparam logic [63:0] O_BASE = 64'h0000_0000_0000_2000;
  localparam logic [63:0] BAD_Q_BASE = 64'h0000_0000_0010_0000;
  localparam int unsigned AXI_LANES = FA_AXI_DATA_W / FA_ELEM_W;
  localparam int unsigned BEATS  = FA_D / AXI_LANES;

  logic clk;
  logic rst_n;

  logic [11:0] s_axil_awaddr;
  logic        s_axil_awvalid;
  logic        s_axil_awready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_wvalid;
  logic        s_axil_wready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_bvalid;
  logic        s_axil_bready;
  logic [11:0] s_axil_araddr;
  logic        s_axil_arvalid;
  logic        s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready;

  logic [63:0] m_axi_araddr;
  logic [7:0]  m_axi_arlen;
  logic [2:0]  m_axi_arsize;
  logic [1:0]  m_axi_arburst;
  logic        m_axi_arvalid;
  logic        m_axi_arready;
  logic [FA_AXI_DATA_W-1:0] m_axi_rdata;
  logic [1:0]  m_axi_rresp;
  logic        m_axi_rlast;
  logic        m_axi_rvalid;
  logic        m_axi_rready;
  logic [63:0] m_axi_awaddr;
  logic [7:0]  m_axi_awlen;
  logic [2:0]  m_axi_awsize;
  logic [1:0]  m_axi_awburst;
  logic        m_axi_awvalid;
  logic        m_axi_awready;
  logic [FA_AXI_DATA_W-1:0] m_axi_wdata;
  logic [FA_AXI_STRB_W-1:0] m_axi_wstrb;
  logic        m_axi_wlast;
  logic        m_axi_wvalid;
  logic        m_axi_wready;
  logic [1:0]  m_axi_bresp;
  logic        m_axi_bvalid;
  logic        m_axi_bready;
  logic        irq;

  fa_accel_top dut (
    .clk,
    .rst_n,
    .s_axil_awaddr,
    .s_axil_awvalid,
    .s_axil_awready,
    .s_axil_wdata,
    .s_axil_wstrb,
    .s_axil_wvalid,
    .s_axil_wready,
    .s_axil_bresp,
    .s_axil_bvalid,
    .s_axil_bready,
    .s_axil_araddr,
    .s_axil_arvalid,
    .s_axil_arready,
    .s_axil_rdata,
    .s_axil_rresp,
    .s_axil_rvalid,
    .s_axil_rready,
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
    .m_axi_rready,
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
    .m_axi_bready,
    .irq
  );

  axi_mem_model #(
    .DATA_W(FA_AXI_DATA_W)
  ) u_mem (
    .clk,
    .rst_n,
    .s_axi_araddr  (m_axi_araddr),
    .s_axi_arlen   (m_axi_arlen),
    .s_axi_arsize  (m_axi_arsize),
    .s_axi_arburst (m_axi_arburst),
    .s_axi_arvalid (m_axi_arvalid),
    .s_axi_arready (m_axi_arready),
    .s_axi_rdata   (m_axi_rdata),
    .s_axi_rresp   (m_axi_rresp),
    .s_axi_rlast   (m_axi_rlast),
    .s_axi_rvalid  (m_axi_rvalid),
    .s_axi_rready  (m_axi_rready),
    .s_axi_awaddr  (m_axi_awaddr),
    .s_axi_awlen   (m_axi_awlen),
    .s_axi_awsize  (m_axi_awsize),
    .s_axi_awburst (m_axi_awburst),
    .s_axi_awvalid (m_axi_awvalid),
    .s_axi_awready (m_axi_awready),
    .s_axi_wdata   (m_axi_wdata),
    .s_axi_wstrb   (m_axi_wstrb),
    .s_axi_wlast   (m_axi_wlast),
    .s_axi_wvalid  (m_axi_wvalid),
    .s_axi_wready  (m_axi_wready),
    .s_axi_bresp   (m_axi_bresp),
    .s_axi_bvalid  (m_axi_bvalid),
    .s_axi_bready  (m_axi_bready)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic fail(input string message);
    begin
      $error("%s", message);
      $fatal(1);
    end
  endtask

  task automatic axil_write(
    input logic [11:0] addr,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      s_axil_awaddr  = addr;
      s_axil_awvalid = 1'b1;
      s_axil_wdata   = data;
      s_axil_wstrb   = 4'hf;
      s_axil_wvalid  = 1'b1;
      s_axil_bready  = 1'b1;
      do @(posedge clk); while (!(s_axil_awready && s_axil_wready));
      @(negedge clk);
      s_axil_awvalid = 1'b0;
      s_axil_wvalid  = 1'b0;
      do @(posedge clk); while (!s_axil_bvalid);
      if (s_axil_bresp !== 2'b00) fail("AXI-Lite write response error");
      @(negedge clk);
      s_axil_bready = 1'b0;
    end
  endtask

  task automatic axil_read(
    input  logic [11:0] addr,
    output logic [31:0] data
  );
    begin
      @(negedge clk);
      s_axil_araddr  = addr;
      s_axil_arvalid = 1'b1;
      s_axil_rready  = 1'b1;
      do @(posedge clk); while (!s_axil_arready);
      @(negedge clk);
      s_axil_arvalid = 1'b0;
      do @(posedge clk); while (!s_axil_rvalid);
      data = s_axil_rdata;
      if (s_axil_rresp !== 2'b00) fail("AXI-Lite read response error");
      @(negedge clk);
      s_axil_rready = 1'b0;
    end
  endtask

  task automatic reset_dut;
    begin
      rst_n          = 1'b0;
      s_axil_awaddr  = '0;
      s_axil_awvalid = 1'b0;
      s_axil_wdata   = '0;
      s_axil_wstrb   = '0;
      s_axil_wvalid  = 1'b0;
      s_axil_bready  = 1'b0;
      s_axil_araddr  = '0;
      s_axil_arvalid = 1'b0;
      s_axil_rready  = 1'b0;
      repeat (6) @(negedge clk);
      rst_n = 1'b1;
      repeat (4) @(negedge clk);
    end
  endtask

  logic [31:0] status;
  logic [31:0] cycles;
  logic [FA_AXI_DATA_W-1:0] got_word;
  int unsigned idx;
  int unsigned poll_count;

  function automatic logic [FA_AXI_DATA_W-1:0] smoke_word(input int unsigned beat);
    logic [FA_AXI_DATA_W-1:0] value;
    begin
      value = '0;
      value[63:0] = 64'h5151_0000_0000_0000 | {56'h0, beat[7:0]};
      if (FA_AXI_DATA_W > 64) begin
        value[FA_AXI_DATA_W-1:64] = {((FA_AXI_DATA_W - 64) / 8){8'h5a}};
      end
      return value;
    end
  endfunction

  initial begin
    reset_dut();

    for (idx = 0; idx < BEATS; idx++) begin
      u_mem.write_word(Q_BASE + (idx * FA_AXI_STRB_W), smoke_word(idx));
      u_mem.write_word(O_BASE + (idx * FA_AXI_STRB_W), {FA_AXI_STRB_W{8'had}});
    end

    axil_write(REG_Q_BASE_L, Q_BASE[31:0]);
    axil_write(REG_Q_BASE_H, Q_BASE[63:32]);
    axil_write(REG_O_BASE_L, O_BASE[31:0]);
    axil_write(REG_O_BASE_H, O_BASE[63:32]);
    axil_write(REG_STRIDE_BYTES, 32'd128);
    axil_write(REG_CTRL, 32'h0000_0005);

    poll_count = 0;
    do begin
      axil_read(REG_STATUS, status);
      if (status[2]) fail("top reported DMA smoke error");
      poll_count++;
      if (poll_count > 200) fail("timeout waiting for top DMA smoke done");
    end while (!status[1]);

    if (status[0]) fail("busy remained high after done");
    if (!irq) fail("irq did not assert with irq_en and done");

    axil_read(REG_CYCLES, cycles);
    if (cycles == 32'd0) fail("cycles did not increment");

    for (idx = 0; idx < BEATS; idx++) begin
      u_mem.read_word(O_BASE + (idx * FA_AXI_STRB_W), got_word);
      if (got_word !== smoke_word(idx)) begin
        $fatal(1, "O[%0d] mismatch got=0x%0x", idx, got_word);
      end
    end

    axil_write(REG_STATUS, 32'h0000_0002);
    axil_read(REG_STATUS, status);
    if (status[1]) fail("done_clear did not clear done");

    axil_write(REG_Q_BASE_L, BAD_Q_BASE[31:0]);
    axil_write(REG_Q_BASE_H, BAD_Q_BASE[63:32]);
    axil_write(REG_CTRL, 32'h0000_0005);

    poll_count = 0;
    do begin
      axil_read(REG_STATUS, status);
      poll_count++;
      if (poll_count > 200) fail("timeout waiting for top DMA smoke error");
    end while (!status[2]);

    if (status[0]) fail("busy remained high after DMA error");
    if (status[1]) fail("done asserted on DMA error");
    if (irq) fail("irq asserted on DMA error without done");

    $display("tb_top_dma_smoke PASS");
    $finish;
  end

  initial begin
    #50000;
    fail("timeout");
  end
endmodule
