`timescale 1ns/1ps

import fa_pkg::*;

module tb_top_compute_s32_smoke #(
  parameter int unsigned ROWS         = 32,
  parameter int unsigned KV_TILE_ROWS = 8,
  parameter int unsigned MEM_WORDS    = 4096,
  parameter int unsigned AXI_MEM_AR_READY_STALL_CYCLES = 0,
  parameter int unsigned AXI_MEM_AW_READY_STALL_CYCLES = 0,
  parameter int unsigned AXI_MEM_W_READY_STALL_CYCLES  = 0,
  parameter int unsigned AXI_MEM_R_VALID_DELAY_CYCLES  = 0,
  parameter int unsigned AXI_MEM_B_VALID_DELAY_CYCLES  = 0,
  parameter logic [63:0] Q_BASE       = 64'h0000_0000_0000_1000,
  parameter logic [63:0] K_BASE       = 64'h0000_0000_0000_2000,
  parameter logic [63:0] V_BASE       = 64'h0000_0000_0000_3000,
  parameter logic [63:0] O_BASE       = 64'h0000_0000_0000_4000
);
  localparam int unsigned AXI_LANES = FA_AXI_DATA_W / FA_ELEM_W;
  localparam int unsigned BEATS_PER_ROW = FA_D / AXI_LANES;
  localparam int unsigned TOTAL_BEATS = ROWS * BEATS_PER_ROW;
  localparam int unsigned MAX_CAUSAL_ROW_READS = (ROWS * (ROWS + 1)) / 2;
  localparam logic [63:0] STRIDE_BYTES = 64'd128;
  localparam logic [63:0] Q_LIMIT = Q_BASE + (ROWS * STRIDE_BYTES);
  localparam logic [63:0] K_LIMIT = K_BASE + (ROWS * STRIDE_BYTES);
  localparam logic [63:0] V_LIMIT = V_BASE + (ROWS * STRIDE_BYTES);
  localparam logic [63:0] O_LIMIT = O_BASE + (ROWS * STRIDE_BYTES);
  localparam logic [63:0] MEM_LIMIT = MEM_WORDS * 64'(FA_AXI_STRB_W);

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

  logic [FA_AXI_DATA_W-1:0] q_beats [0:TOTAL_BEATS-1];
  logic [FA_AXI_DATA_W-1:0] k_beats [0:TOTAL_BEATS-1];
  logic [FA_AXI_DATA_W-1:0] v_beats [0:TOTAL_BEATS-1];
  logic [FA_AXI_DATA_W-1:0] o_golden_beats [0:TOTAL_BEATS-1];
  logic        saw_q_buffer_load_done;
  logic        saw_k_buffer_load_done;
  logic        saw_v_buffer_load_done;
  logic        saw_oob_kv_read;
  int unsigned q_row_read_count;
  int unsigned k_row_read_count;
  int unsigned v_row_read_count;
  int unsigned o_row_write_count;
  int unsigned oob_kv_read_count;

  fa_accel_top #(
    .COMPUTE_ROWS (ROWS),
    .KV_TILE_ROWS (KV_TILE_ROWS)
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

  axi_mem_model #(
    .DATA_W                (FA_AXI_DATA_W),
    .MEM_WORDS             (MEM_WORDS),
    .AR_READY_STALL_CYCLES (AXI_MEM_AR_READY_STALL_CYCLES),
    .AW_READY_STALL_CYCLES (AXI_MEM_AW_READY_STALL_CYCLES),
    .W_READY_STALL_CYCLES (AXI_MEM_W_READY_STALL_CYCLES),
    .R_VALID_DELAY_CYCLES (AXI_MEM_R_VALID_DELAY_CYCLES),
    .B_VALID_DELAY_CYCLES (AXI_MEM_B_VALID_DELAY_CYCLES)
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

  initial begin : static_config_checks
    if (dut.COMPUTE_ROWS != ROWS) fail("top compute smoke COMPUTE_ROWS override did not apply");
    if (dut.KV_TILE_ROWS != KV_TILE_ROWS) fail("top compute smoke KV_TILE_ROWS override did not apply");
    if (!((Q_LIMIT <= K_BASE) && (K_LIMIT <= V_BASE) && (V_LIMIT <= O_BASE))) begin
      fail("top compute smoke Q/K/V/O base ranges overlap");
    end
    if (O_LIMIT > MEM_LIMIT) fail("top compute smoke axi_mem_model MEM_WORDS is too small");
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      saw_q_buffer_load_done <= 1'b0;
      saw_k_buffer_load_done <= 1'b0;
      saw_v_buffer_load_done <= 1'b0;
      saw_oob_kv_read        <= 1'b0;
      q_row_read_count       <= 0;
      k_row_read_count       <= 0;
      v_row_read_count       <= 0;
      o_row_write_count      <= 0;
      oob_kv_read_count      <= 0;
    end else begin
      saw_q_buffer_load_done <= saw_q_buffer_load_done ||
                                dut.u_q_buffer.load_done_o;
      saw_k_buffer_load_done <= saw_k_buffer_load_done ||
                                dut.u_kv_buffer.k_load_done_o;
      saw_v_buffer_load_done <= saw_v_buffer_load_done ||
                                dut.u_kv_buffer.v_load_done_o;

      if (m_axi_arvalid && m_axi_arready) begin
        if ((m_axi_araddr >= Q_BASE) && (m_axi_araddr < Q_LIMIT)) begin
          q_row_read_count <= q_row_read_count + 1;
        end else if ((m_axi_araddr >= K_BASE) && (m_axi_araddr < V_BASE)) begin
          k_row_read_count <= k_row_read_count + 1;
          if (m_axi_araddr >= K_LIMIT) begin
            saw_oob_kv_read   <= 1'b1;
            oob_kv_read_count <= oob_kv_read_count + 1;
          end
        end else if ((m_axi_araddr >= V_BASE) && (m_axi_araddr < O_BASE)) begin
          v_row_read_count <= v_row_read_count + 1;
          if (m_axi_araddr >= V_LIMIT) begin
            saw_oob_kv_read   <= 1'b1;
            oob_kv_read_count <= oob_kv_read_count + 1;
          end
        end
      end

      if (m_axi_awvalid && m_axi_awready &&
          (m_axi_awaddr >= O_BASE) &&
          (m_axi_awaddr < O_LIMIT)) begin
        o_row_write_count <= o_row_write_count + 1;
      end
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

  task automatic dump_o_beats(input string path);
    int fd;
    logic [FA_AXI_DATA_W-1:0] dump_word;
    int unsigned dump_idx;
    begin
      fd = $fopen(path, "w");
      if (fd == 0) fail({"failed to open O dump file: ", path});

      for (dump_idx = 0; dump_idx < TOTAL_BEATS; dump_idx++) begin
        u_mem.read_word(O_BASE + (dump_idx * FA_AXI_STRB_W), dump_word);
        if (FA_AXI_DATA_W == 128) begin
          $fdisplay(fd, "%032x", dump_word);
        end else begin
          $fdisplay(fd, "%016x", dump_word);
        end
      end
      $fclose(fd);
      $display("Dumped O beats to %s", path);
    end
  endtask

  logic [31:0] status;
  logic [31:0] cycles;
  logic [FA_AXI_DATA_W-1:0] got_word;
  string q_path;
  string k_path;
  string v_path;
  string o_golden_path;
  string dump_o_beats_path;
  int unsigned idx;
  int unsigned poll_count;

  initial begin
    q_path = "artifacts/vectors/s32_d64_seed103/s32_d64_seed103_Q_beats128.hex";
    k_path = "artifacts/vectors/s32_d64_seed103/s32_d64_seed103_K_beats128.hex";
    v_path = "artifacts/vectors/s32_d64_seed103/s32_d64_seed103_V_beats128.hex";
    o_golden_path = "artifacts/vectors/s32_d64_seed103/s32_d64_seed103_O_golden_beats128.hex";
    if ($value$plusargs("Q_BEATS128=%s", q_path)) begin end
    if ($value$plusargs("K_BEATS128=%s", k_path)) begin end
    if ($value$plusargs("V_BEATS128=%s", v_path)) begin end
    if ($value$plusargs("O_GOLDEN_BEATS128=%s", o_golden_path)) begin end
    if ($value$plusargs("Q_BEATS64=%s", q_path)) begin end
    if ($value$plusargs("K_BEATS64=%s", k_path)) begin end
    if ($value$plusargs("V_BEATS64=%s", v_path)) begin end
    if ($value$plusargs("O_GOLDEN_BEATS64=%s", o_golden_path)) begin end

    reset_dut();

    $readmemh(q_path, q_beats);
    $readmemh(k_path, k_beats);
    $readmemh(v_path, v_beats);
    $readmemh(o_golden_path, o_golden_beats);

    for (idx = 0; idx < TOTAL_BEATS; idx++) begin
      u_mem.write_word(Q_BASE + (idx * FA_AXI_STRB_W), q_beats[idx]);
      u_mem.write_word(K_BASE + (idx * FA_AXI_STRB_W), k_beats[idx]);
      u_mem.write_word(V_BASE + (idx * FA_AXI_STRB_W), v_beats[idx]);
      u_mem.write_word(O_BASE + (idx * FA_AXI_STRB_W), {FA_AXI_STRB_W{8'had}});
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
      if (status[2]) fail("top reported compute smoke error");
      poll_count++;
      if (poll_count > 2000000) begin
        $display("TIMEOUT_DEBUG state=%0d q=%0d tile_base=%0d tile_off=%0d k=%0d wr_beat=%0d rd_valid=%0b rd_ready=%0b rd_done=%0b wr_valid=%0b wr_ready=%0b wr_done=%0b row_busy=%0b row_valid_o=%0b cycles=%0d",
                 dut.top_state,
                 dut.compute_q_idx,
                 dut.compute_kv_tile_base_idx,
                 dut.compute_key_in_tile_idx,
                 dut.compute_k_idx,
                 dut.compute_wr_beat_idx,
                 dut.rd_valid,
                 dut.rd_out_ready,
                 dut.rd_done,
                 dut.wr_in_valid,
                 dut.wr_in_ready,
                 dut.wr_done,
                 dut.row_engine_busy,
                 dut.row_engine_valid_o,
                 dut.cycles);
        fail("timeout waiting for top compute smoke done");
      end
    end while (!status[1]);

    if (status[0]) fail("busy remained high after compute done");
    if (!irq) fail("irq did not assert with irq_en and compute done");
    if (!saw_q_buffer_load_done) fail("Q buffer was not loaded during compute smoke");
    if (!saw_k_buffer_load_done) fail("K buffer was not loaded during compute smoke");
    if (!saw_v_buffer_load_done) fail("V buffer was not loaded during compute smoke");
    if (saw_oob_kv_read) begin
      $fatal(1, "top compute smoke observed %0d out-of-range K/V row DMA reads",
             oob_kv_read_count);
    end
    if (q_row_read_count != ROWS) begin
      $fatal(1, "top compute smoke expected %0d Q row reads, observed %0d",
             ROWS, q_row_read_count);
    end
    if ((k_row_read_count < ROWS) || (k_row_read_count > MAX_CAUSAL_ROW_READS)) begin
      $fatal(1, "top compute smoke expected K row reads in [%0d,%0d], observed %0d",
             ROWS, MAX_CAUSAL_ROW_READS, k_row_read_count);
    end
    if ((v_row_read_count < ROWS) || (v_row_read_count > MAX_CAUSAL_ROW_READS)) begin
      $fatal(1, "top compute smoke expected V row reads in [%0d,%0d], observed %0d",
             ROWS, MAX_CAUSAL_ROW_READS, v_row_read_count);
    end
    if (o_row_write_count != ROWS) begin
      $fatal(1, "top compute smoke expected %0d O row writes, observed %0d",
             ROWS, o_row_write_count);
    end

    axil_read(REG_CYCLES, cycles);
    if (cycles == 32'd0) fail("cycles did not increment");

    for (idx = 0; idx < TOTAL_BEATS; idx++) begin
      u_mem.read_word(O_BASE + (idx * FA_AXI_STRB_W), got_word);
      if (got_word !== o_golden_beats[idx]) begin
        $fatal(1,
               "top compute O beat %0d mismatch got=0x%0x expected=0x%0x",
               idx, got_word, o_golden_beats[idx]);
      end
    end

    if ($value$plusargs("DUMP_O_BEATS128=%s", dump_o_beats_path)) begin
      dump_o_beats(dump_o_beats_path);
    end else if ($value$plusargs("DUMP_O_BEATS64=%s", dump_o_beats_path)) begin
      dump_o_beats(dump_o_beats_path);
    end

    $display("tb_top_compute_smoke PASS S=%0d D=64 AXI_DATA_W=%0d KV_TILE_ROWS=%0d",
             ROWS, FA_AXI_DATA_W, KV_TILE_ROWS);
    $finish;
  end

  initial begin
    #60000000;
    fail("timeout");
  end
endmodule
