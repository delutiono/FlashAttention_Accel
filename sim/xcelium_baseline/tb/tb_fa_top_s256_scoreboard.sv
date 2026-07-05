`timescale 1ns/1ps

module tb_fa_top_s256_scoreboard;
  localparam logic [11:0] REG_CTRL     = 12'h000;
  localparam logic [11:0] REG_STATUS   = 12'h004;
  localparam logic [11:0] REG_CFG      = 12'h008;
  localparam logic [11:0] REG_Q_BASE_L = 12'h014;
  localparam logic [11:0] REG_Q_BASE_H = 12'h018;
  localparam logic [11:0] REG_K_BASE_L = 12'h01c;
  localparam logic [11:0] REG_K_BASE_H = 12'h020;
  localparam logic [11:0] REG_V_BASE_L = 12'h024;
  localparam logic [11:0] REG_V_BASE_H = 12'h028;
  localparam logic [11:0] REG_O_BASE_L = 12'h02c;
  localparam logic [11:0] REG_O_BASE_H = 12'h030;
  localparam logic [11:0] REG_STRIDE   = 12'h034;
  localparam logic [11:0] REG_SCALE    = 12'h03c;
  localparam logic [11:0] REG_CYCLES   = 12'h040;

  localparam logic [63:0] Q_BASE = 64'h0000_0000_0000_1000;
  localparam logic [63:0] K_BASE = 64'h0000_0000_0000_9000;
  localparam logic [63:0] V_BASE = 64'h0000_0000_0001_1000;
  localparam logic [63:0] O_BASE = 64'h0000_0000_0001_9000;
  localparam int unsigned ROWS = 256;
  localparam int unsigned D = 64;
  localparam int unsigned BEATS_PER_ROW = 8;
  localparam int unsigned EXPECTED_BEATS = ROWS * BEATS_PER_ROW;
  localparam int unsigned MAX_CYCLES = 600000;

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
  wire         m_axi_arready;
  wire [127:0] m_axi_rdata;
  wire [1:0]   m_axi_rresp;
  wire         m_axi_rlast;
  wire         m_axi_rvalid;
  wire         m_axi_rready;
  wire [63:0]  m_axi_awaddr;
  wire [7:0]   m_axi_awlen;
  wire [2:0]   m_axi_awsize;
  wire [1:0]   m_axi_awburst;
  wire         m_axi_awvalid;
  wire         m_axi_awready;
  wire [127:0] m_axi_wdata;
  wire [15:0]  m_axi_wstrb;
  wire         m_axi_wlast;
  wire         m_axi_wvalid;
  wire         m_axi_wready;
  wire [1:0]   m_axi_bresp;
  wire         m_axi_bvalid;
  wire         m_axi_bready;

  int unsigned cycle_count;
  int unsigned o_write_beats;
  string q_path;
  string k_path;
  string v_path;
  string dump_path;

  fa_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready), .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready), .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready), .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready), .irq(irq),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready), .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready), .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready)
  );

  axi_mem_model_128 #(.MEM_WORDS(16384)) u_mem (
    .clk(clk), .rst_n(rst_n),
    .s_axi_araddr(m_axi_araddr), .s_axi_arlen(m_axi_arlen),
    .s_axi_arsize(m_axi_arsize), .s_axi_arburst(m_axi_arburst),
    .s_axi_arvalid(m_axi_arvalid), .s_axi_arready(m_axi_arready),
    .s_axi_rdata(m_axi_rdata), .s_axi_rresp(m_axi_rresp),
    .s_axi_rlast(m_axi_rlast), .s_axi_rvalid(m_axi_rvalid),
    .s_axi_rready(m_axi_rready), .s_axi_awaddr(m_axi_awaddr),
    .s_axi_awlen(m_axi_awlen), .s_axi_awsize(m_axi_awsize),
    .s_axi_awburst(m_axi_awburst), .s_axi_awvalid(m_axi_awvalid),
    .s_axi_awready(m_axi_awready), .s_axi_wdata(m_axi_wdata),
    .s_axi_wstrb(m_axi_wstrb), .s_axi_wlast(m_axi_wlast),
    .s_axi_wvalid(m_axi_wvalid), .s_axi_wready(m_axi_wready),
    .s_axi_bresp(m_axi_bresp), .s_axi_bvalid(m_axi_bvalid),
    .s_axi_bready(m_axi_bready)
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

  task automatic load_beats128(input string path, input logic [63:0] base);
    int fd;
    int code;
    int count;
    logic [127:0] data;
    begin
      fd = $fopen(path, "r");
      if (fd == 0) fail({"could not open ", path});
      count = 0;
      while (!$feof(fd)) begin
        code = $fscanf(fd, "%h\n", data);
        if (code == 1) begin
          u_mem.write_word(base + (count * 16), data);
          count = count + 1;
        end
      end
      $fclose(fd);
      if (count != EXPECTED_BEATS) begin
        $display("FAIL: %s loaded beats=%0d expected=%0d", path, count, EXPECTED_BEATS);
        $fatal(1);
      end
    end
  endtask

  task automatic dump_o_words16(input string path);
    int fd;
    int row;
    int beat;
    int lane;
    logic [127:0] data;
    begin
      fd = $fopen(path, "w");
      if (fd == 0) fail({"could not open dump ", path});
      for (row = 0; row < ROWS; row = row + 1) begin
        for (beat = 0; beat < BEATS_PER_ROW; beat = beat + 1) begin
          u_mem.read_word(O_BASE + ((row * BEATS_PER_ROW + beat) * 16), data);
          for (lane = 0; lane < 8; lane = lane + 1) begin
            $fdisplay(fd, "%04h", data[lane*16 +: 16]);
          end
        end
      end
      $fclose(fd);
    end
  endtask

  task automatic axil_write(input logic [11:0] addr, input logic [31:0] data);
    begin
      @(posedge clk);
      s_axil_awaddr <= addr;
      s_axil_awvalid <= 1'b1;
      while (!s_axil_awready) @(posedge clk);
      @(posedge clk);
      s_axil_awvalid <= 1'b0;
      s_axil_wdata <= data;
      s_axil_wstrb <= 4'hf;
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

  task automatic axil_read(input logic [11:0] addr, output logic [31:0] data);
    begin
      @(posedge clk);
      s_axil_araddr <= addr;
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

  logic [31:0] status;
  logic [31:0] cycles_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
      o_write_beats <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count > MAX_CYCLES) fail("timeout waiting for scoreboard run");
      if (m_axi_wvalid && m_axi_wready &&
          (m_axi_awaddr >= O_BASE) && (m_axi_awaddr < (O_BASE + 64'd32768))) begin
        o_write_beats <= o_write_beats + 1;
      end
    end
  end

  initial begin
    if (!$value$plusargs("Q_BEATS128=%s", q_path)) fail("missing +Q_BEATS128");
    if (!$value$plusargs("K_BEATS128=%s", k_path)) fail("missing +K_BEATS128");
    if (!$value$plusargs("V_BEATS128=%s", v_path)) fail("missing +V_BEATS128");
    if (!$value$plusargs("DUMP_O_WORDS16=%s", dump_path)) fail("missing +DUMP_O_WORDS16");

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

    load_beats128(q_path, Q_BASE);
    load_beats128(k_path, K_BASE);
    load_beats128(v_path, V_BASE);

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    axil_write(REG_Q_BASE_L, Q_BASE[31:0]);
    axil_write(REG_Q_BASE_H, Q_BASE[63:32]);
    axil_write(REG_K_BASE_L, K_BASE[31:0]);
    axil_write(REG_K_BASE_H, K_BASE[63:32]);
    axil_write(REG_V_BASE_L, V_BASE[31:0]);
    axil_write(REG_V_BASE_H, V_BASE[63:32]);
    axil_write(REG_O_BASE_L, O_BASE[31:0]);
    axil_write(REG_O_BASE_H, O_BASE[63:32]);
    axil_write(REG_STRIDE, 32'd128);
    axil_write(REG_CFG, 32'h0000_0001);
    axil_write(REG_SCALE, 32'h0000_2000);
    axil_write(REG_CTRL, 32'h0000_0005);

    do begin
      axil_read(REG_STATUS, status);
      repeat (25) @(posedge clk);
    end while (status[1] !== 1'b1 && status[2] !== 1'b1);

    if (status[2]) fail("scoreboard run completed with STATUS.ERROR");
    axil_read(REG_CYCLES, cycles_reg);
    if (o_write_beats != EXPECTED_BEATS) fail("unexpected O write beat count");
    dump_o_words16(dump_path);

    $display("PASS: fa_top S256 scoreboard RTL run cycles=%0d o_write_beats=%0d dump=%s",
             cycles_reg, o_write_beats, dump_path);
    $finish;
  end
endmodule
