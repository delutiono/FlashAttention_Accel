`timescale 1ns/1ps

module tb_fa_top_axi_lite_smoke;
  localparam logic [11:0] REG_CTRL      = 12'h000;
  localparam logic [11:0] REG_STATUS    = 12'h004;
  localparam logic [11:0] REG_CFG       = 12'h008;
  localparam logic [11:0] REG_Q_BASE_L  = 12'h014;
  localparam logic [11:0] REG_Q_BASE_H  = 12'h018;
  localparam logic [11:0] REG_K_BASE_L  = 12'h01c;
  localparam logic [11:0] REG_K_BASE_H  = 12'h020;
  localparam logic [11:0] REG_V_BASE_L  = 12'h024;
  localparam logic [11:0] REG_V_BASE_H  = 12'h028;
  localparam logic [11:0] REG_O_BASE_L  = 12'h02c;
  localparam logic [11:0] REG_O_BASE_H  = 12'h030;
  localparam logic [11:0] REG_STRIDE    = 12'h034;
  localparam logic [11:0] REG_NEG_LARGE = 12'h038;
  localparam logic [11:0] REG_SCALE     = 12'h03c;
  localparam logic [11:0] REG_CYCLES    = 12'h040;

  logic clk;
  logic rst_n;

  logic [11:0] s_axil_awaddr;
  logic        s_axil_awvalid;
  wire         s_axil_awready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_wvalid;
  wire         s_axil_wready;
  wire [1:0]   s_axil_bresp;
  wire         s_axil_bvalid;
  logic        s_axil_bready;
  logic [11:0] s_axil_araddr;
  logic        s_axil_arvalid;
  wire         s_axil_arready;
  wire [31:0]  s_axil_rdata;
  wire [1:0]   s_axil_rresp;
  wire         s_axil_rvalid;
  logic        s_axil_rready;
  wire         irq;

  wire [63:0]  m_axi_araddr;
  wire [7:0]   m_axi_arlen;
  wire [2:0]   m_axi_arsize;
  wire [1:0]   m_axi_arburst;
  wire         m_axi_arvalid;
  logic        m_axi_arready;
  logic [127:0] m_axi_rdata;
  logic [1:0]  m_axi_rresp;
  logic        m_axi_rlast;
  logic        m_axi_rvalid;
  wire         m_axi_rready;
  wire [63:0]  m_axi_awaddr;
  wire [7:0]   m_axi_awlen;
  wire [2:0]   m_axi_awsize;
  wire [1:0]   m_axi_awburst;
  wire         m_axi_awvalid;
  logic        m_axi_awready;
  wire [127:0] m_axi_wdata;
  wire [15:0]  m_axi_wstrb;
  wire         m_axi_wlast;
  wire         m_axi_wvalid;
  logic        m_axi_wready;
  logic [1:0]  m_axi_bresp;
  logic        m_axi_bvalid;
  wire         m_axi_bready;

  fa_top dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .irq(irq),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic fail(input string msg);
    begin
      $display("FAIL: %s", msg);
      $fatal(1);
    end
  endtask

  task automatic axil_write(
    input logic [11:0] addr,
    input logic [31:0] data
  );
    begin
      @(posedge clk);
      s_axil_awaddr  <= addr;
      s_axil_awvalid <= 1'b1;
      while (!s_axil_awready) @(posedge clk);
      @(posedge clk);
      s_axil_awvalid <= 1'b0;

      s_axil_wdata  <= data;
      s_axil_wstrb  <= 4'hf;
      s_axil_wvalid <= 1'b1;
      while (!s_axil_wready) @(posedge clk);
      @(posedge clk);
      s_axil_wvalid <= 1'b0;

      s_axil_bready <= 1'b1;
      while (!s_axil_bvalid) @(posedge clk);
      if (s_axil_bresp !== 2'b00) fail("AXI-Lite write response error");
      @(posedge clk);
      s_axil_bready <= 1'b0;
    end
  endtask

  task automatic axil_read(
    input  logic [11:0] addr,
    output logic [31:0] data
  );
    begin
      @(posedge clk);
      s_axil_araddr  <= addr;
      s_axil_arvalid <= 1'b1;
      while (!s_axil_arready) @(posedge clk);
      @(posedge clk);
      s_axil_arvalid <= 1'b0;

      s_axil_rready <= 1'b1;
      while (!s_axil_rvalid) @(posedge clk);
      if (s_axil_rresp !== 2'b00) fail("AXI-Lite read response error");
      data = s_axil_rdata;
      @(posedge clk);
      s_axil_rready <= 1'b0;
    end
  endtask

  task automatic expect_eq(
    input string tag,
    input logic [31:0] got,
    input logic [31:0] exp
  );
    begin
      if (got !== exp) begin
        $display("FAIL: %s got=0x%08h exp=0x%08h", tag, got, exp);
        $fatal(1);
      end
    end
  endtask

  logic [31:0] rd;

  initial begin
    rst_n = 1'b0;
    s_axil_awaddr = '0;
    s_axil_awvalid = 1'b0;
    s_axil_wdata = '0;
    s_axil_wstrb = '0;
    s_axil_wvalid = 1'b0;
    s_axil_bready = 1'b0;
    s_axil_araddr = '0;
    s_axil_arvalid = 1'b0;
    s_axil_rready = 1'b0;
    m_axi_arready = 1'b0;
    m_axi_rdata = '0;
    m_axi_rresp = 2'b00;
    m_axi_rlast = 1'b0;
    m_axi_rvalid = 1'b0;
    m_axi_awready = 1'b0;
    m_axi_wready = 1'b0;
    m_axi_bresp = 2'b00;
    m_axi_bvalid = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    axil_read(REG_STATUS, rd);
    expect_eq("default STATUS", rd, 32'h0000_0000);
    axil_read(REG_CFG, rd);
    expect_eq("default CFG", rd, 32'h0000_0001);
    axil_read(REG_STRIDE, rd);
    expect_eq("default STRIDE", rd, 32'd128);
    axil_read(REG_NEG_LARGE, rd);
    expect_eq("default NEG_LARGE", rd, 32'hfff0_0000);
    axil_read(REG_SCALE, rd);
    expect_eq("default SCALE", rd, 32'h0000_2000);
    axil_read(REG_CYCLES, rd);
    expect_eq("default CYCLES", rd, 32'h0000_0000);

    axil_write(REG_Q_BASE_L, 32'h0000_1000);
    axil_write(REG_Q_BASE_H, 32'h0000_0001);
    axil_write(REG_K_BASE_L, 32'h0000_9000);
    axil_write(REG_K_BASE_H, 32'h0000_0002);
    axil_write(REG_V_BASE_L, 32'h0001_1000);
    axil_write(REG_V_BASE_H, 32'h0000_0003);
    axil_write(REG_O_BASE_L, 32'h0001_9000);
    axil_write(REG_O_BASE_H, 32'h0000_0004);
    axil_write(REG_CTRL, 32'h0000_0004);

    axil_read(REG_Q_BASE_L, rd);
    expect_eq("Q_BASE_L", rd, 32'h0000_1000);
    axil_read(REG_Q_BASE_H, rd);
    expect_eq("Q_BASE_H", rd, 32'h0000_0001);
    axil_read(REG_K_BASE_L, rd);
    expect_eq("K_BASE_L", rd, 32'h0000_9000);
    axil_read(REG_K_BASE_H, rd);
    expect_eq("K_BASE_H", rd, 32'h0000_0002);
    axil_read(REG_V_BASE_L, rd);
    expect_eq("V_BASE_L", rd, 32'h0001_1000);
    axil_read(REG_V_BASE_H, rd);
    expect_eq("V_BASE_H", rd, 32'h0000_0003);
    axil_read(REG_O_BASE_L, rd);
    expect_eq("O_BASE_L", rd, 32'h0001_9000);
    axil_read(REG_O_BASE_H, rd);
    expect_eq("O_BASE_H", rd, 32'h0000_0004);
    axil_read(REG_CTRL, rd);
    expect_eq("CTRL irq_en readback", rd, 32'h0000_0004);

    $display("PASS: fa_top AXI-Lite register smoke");
    $finish;
  end
endmodule
