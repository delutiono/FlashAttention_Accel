`timescale 1ns/1ps

import fa_pkg::*;

module tb_top_compute_s4_smoke;
  localparam logic [63:0] Q_BASE = 64'h0000_0000_0000_1000;
  localparam logic [63:0] K_BASE = 64'h0000_0000_0000_2000;
  localparam logic [63:0] V_BASE = 64'h0000_0000_0000_3000;
  localparam logic [63:0] O_BASE = 64'h0000_0000_0000_4000;
  localparam int unsigned ROWS = 4;
  localparam int unsigned BEATS_PER_ROW = 16;
  localparam int unsigned TOTAL_BEATS = ROWS * BEATS_PER_ROW;

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
  logic [63:0] m_axi_rdata;
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
  logic [63:0] m_axi_wdata;
  logic [7:0]  m_axi_wstrb;
  logic        m_axi_wlast;
  logic        m_axi_wvalid;
  logic        m_axi_wready;
  logic [1:0]  m_axi_bresp;
  logic        m_axi_bvalid;
  logic        m_axi_bready;
  logic        irq;

  logic [63:0] q_beats [0:TOTAL_BEATS-1];
  logic [63:0] k_beats [0:TOTAL_BEATS-1];
  logic [63:0] v_beats [0:TOTAL_BEATS-1];
  logic [63:0] o_golden_beats [0:TOTAL_BEATS-1];
  logic        saw_q_buffer_load_done;
  logic        saw_k_buffer_load_done;
  logic        saw_v_buffer_load_done;

  fa_accel_top #(
    .COMPUTE_ROWS (ROWS),
    .KV_TILE_ROWS (2)
  ) dut (
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

  initial begin : static_config_checks
    if (dut.COMPUTE_ROWS != ROWS) begin
      fail("top compute smoke COMPUTE_ROWS override did not apply");
    end
    if (dut.KV_TILE_ROWS != 2) begin
      fail("top compute smoke KV_TILE_ROWS override did not apply");
    end
  end

  axi_mem_model u_mem (
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      saw_q_buffer_load_done <= 1'b0;
      saw_k_buffer_load_done <= 1'b0;
      saw_v_buffer_load_done <= 1'b0;
    end else begin
      saw_q_buffer_load_done <= saw_q_buffer_load_done ||
                                dut.u_q_buffer.load_done_o;
      saw_k_buffer_load_done <= saw_k_buffer_load_done ||
                                dut.u_kv_buffer.k_load_done_o;
      saw_v_buffer_load_done <= saw_v_buffer_load_done ||
                                dut.u_kv_buffer.v_load_done_o;
    end
  end

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
  logic [63:0] got_word;
  string dump_o_beats64_path;
  int unsigned idx;
  int unsigned poll_count;

  task automatic dump_o_beats64(input string path);
    int fd;
    logic [63:0] dump_word;
    int unsigned dump_idx;
    begin
      fd = $fopen(path, "w");
      if (fd == 0) begin
        fail({"failed to open O dump file: ", path});
      end

      for (dump_idx = 0; dump_idx < TOTAL_BEATS; dump_idx++) begin
        u_mem.read_word(O_BASE + (dump_idx * 8), dump_word);
        $fdisplay(fd, "%016x", dump_word);
      end
      $fclose(fd);
      $display("Dumped O beats64 to %s", path);
    end
  endtask

  initial begin
    reset_dut();

    $readmemh("test_vectors/generated/s4_d64_seed100/s4_d64_seed100_Q_beats64.hex", q_beats);
    $readmemh("test_vectors/generated/s4_d64_seed100/s4_d64_seed100_K_beats64.hex", k_beats);
    $readmemh("test_vectors/generated/s4_d64_seed100/s4_d64_seed100_V_beats64.hex", v_beats);
    $readmemh("test_vectors/generated/s4_d64_seed100/s4_d64_seed100_O_golden_beats64.hex", o_golden_beats);

    for (idx = 0; idx < TOTAL_BEATS; idx++) begin
      u_mem.write_word(Q_BASE + (idx * 8), q_beats[idx]);
      u_mem.write_word(K_BASE + (idx * 8), k_beats[idx]);
      u_mem.write_word(V_BASE + (idx * 8), v_beats[idx]);
      u_mem.write_word(O_BASE + (idx * 8), 64'h0bad_0bad_0bad_0bad);
    end

    axil_write(REG_Q_BASE_L, Q_BASE[31:0]);
    axil_write(REG_Q_BASE_H, Q_BASE[63:32]);
    axil_write(REG_K_BASE_L, K_BASE[31:0]);
    axil_write(REG_K_BASE_H, K_BASE[63:32]);
    axil_write(REG_V_BASE_L, V_BASE[31:0]);
    axil_write(REG_V_BASE_H, V_BASE[63:32]);
    axil_write(REG_O_BASE_L, O_BASE[31:0]);
    axil_write(REG_O_BASE_H, O_BASE[63:32]);
    axil_write(REG_STRIDE_BYTES, 32'd128);
    axil_write(REG_CFG, 32'h8000_0001);
    axil_write(REG_CTRL, 32'h0000_0005);

    poll_count = 0;
    do begin
      axil_read(REG_STATUS, status);
      if (status[2]) fail("top reported compute S4 smoke error");
      poll_count++;
      if (poll_count > 5000) fail("timeout waiting for top compute S4 smoke done");
    end while (!status[1]);

    if (status[0]) fail("busy remained high after compute done");
    if (!irq) fail("irq did not assert with irq_en and compute done");
    if (!saw_q_buffer_load_done) fail("Q buffer was not loaded during compute smoke");
    if (!saw_k_buffer_load_done) fail("K buffer was not loaded during compute smoke");
    if (!saw_v_buffer_load_done) fail("V buffer was not loaded during compute smoke");

    axil_read(REG_CYCLES, cycles);
    if (cycles == 32'd0) fail("cycles did not increment");

    for (idx = 0; idx < TOTAL_BEATS; idx++) begin
      u_mem.read_word(O_BASE + (idx * 8), got_word);
      if (got_word !== o_golden_beats[idx]) begin
        $fatal(1,
               "S4 compute O beat %0d mismatch got=0x%016x expected=0x%016x",
               idx, got_word, o_golden_beats[idx]);
      end
    end

    if ($value$plusargs("DUMP_O_BEATS64=%s", dump_o_beats64_path)) begin
      dump_o_beats64(dump_o_beats64_path);
    end

    $display("tb_top_compute_s4_smoke PASS full S=4 D=64");
    $finish;
  end

  initial begin
    #2000000;
    fail("timeout");
  end
endmodule
