`timescale 1ns/1ps

module tb_fa_top_zero_s256;
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
  localparam logic [11:0] REG_SCALE     = 12'h03c;
  localparam logic [11:0] REG_CYCLES    = 12'h040;

  localparam logic [63:0] Q_BASE = 64'h0000_0000_0000_1000;
  localparam logic [63:0] K_BASE = 64'h0000_0000_0000_9000;
  localparam logic [63:0] V_BASE = 64'h0000_0000_0001_1000;
  localparam logic [63:0] O_BASE = 64'h0000_0000_0001_9000;
  localparam logic [63:0] O_LIMIT = O_BASE + 64'd32768;
  localparam int unsigned EXPECTED_O_BEATS = 2048;
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
  int unsigned o_write_bursts;
  int unsigned q_start_count;
  int unsigned k_start_count;
  int unsigned v_start_count;
  int unsigned o_start_count;
  int unsigned pm_cmd_count;
  int unsigned dma_done_count;
  int unsigned dma_read_done_count;
  int unsigned dma_write_done_count;
  int unsigned axi_ar_count;
  int unsigned axi_r_count;
  int unsigned axi_aw_count;
  int unsigned axi_w_count;
  int unsigned axi_b_count;
  int unsigned init_fire_count;
  int unsigned score_issue_count;
  int unsigned complete_count;
  int unsigned fin_req_count;
  int unsigned fin_o_count;
  int unsigned fin_done_count;
  logic        write_is_o_q;

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

`ifdef FA_GATE_ENABLE_SDF
  initial begin : sdf_annotation
    $display("INFO: annotating fa_top SDF file timing/fa_top_mapped.sdf");
    $sdf_annotate("timing/fa_top_mapped.sdf", dut, , "sdf_annotate.log", "TYPICAL");
  end
`endif

  axi_mem_model_128 #(
    .MEM_WORDS(16384)
  ) u_mem (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_araddr(m_axi_araddr),
    .s_axi_arlen(m_axi_arlen),
    .s_axi_arsize(m_axi_arsize),
    .s_axi_arburst(m_axi_arburst),
    .s_axi_arvalid(m_axi_arvalid),
    .s_axi_arready(m_axi_arready),
    .s_axi_rdata(m_axi_rdata),
    .s_axi_rresp(m_axi_rresp),
    .s_axi_rlast(m_axi_rlast),
    .s_axi_rvalid(m_axi_rvalid),
    .s_axi_rready(m_axi_rready),
    .s_axi_awaddr(m_axi_awaddr),
    .s_axi_awlen(m_axi_awlen),
    .s_axi_awsize(m_axi_awsize),
    .s_axi_awburst(m_axi_awburst),
    .s_axi_awvalid(m_axi_awvalid),
    .s_axi_awready(m_axi_awready),
    .s_axi_wdata(m_axi_wdata),
    .s_axi_wstrb(m_axi_wstrb),
    .s_axi_wlast(m_axi_wlast),
    .s_axi_wvalid(m_axi_wvalid),
    .s_axi_wready(m_axi_wready),
    .s_axi_bresp(m_axi_bresp),
    .s_axi_bvalid(m_axi_bvalid),
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

`ifdef FA_GATE_TRACE
  int unsigned trace_cycles_left;
  int unsigned trace_r_handshake_count;
  logic trace_active;
  logic trace_write_x_seen;
  logic trace_wr_beat_x_seen;

  wire [1:0] trace_dma_state = {dut.\u_dma_u_read_state_reg[1] ,
                                dut.\u_dma_u_read_state_reg[0] };
  wire [15:0] trace_beats_left = {
      dut.\u_dma_u_read_beats_left_reg[15] , dut.\u_dma_u_read_beats_left_reg[14] ,
      dut.\u_dma_u_read_beats_left_reg[13] , dut.\u_dma_u_read_beats_left_reg[12] ,
      dut.\u_dma_u_read_beats_left_reg[11] , dut.\u_dma_u_read_beats_left_reg[10] ,
      dut.\u_dma_u_read_beats_left_reg[9] , dut.\u_dma_u_read_beats_left_reg[8] ,
      dut.\u_dma_u_read_beats_left_reg[7] , dut.\u_dma_u_read_beats_left_reg[6] ,
      dut.\u_dma_u_read_beats_left_reg[5] , dut.\u_dma_u_read_beats_left_reg[4] ,
      dut.\u_dma_u_read_beats_left_reg[3] , dut.\u_dma_u_read_beats_left_reg[2] ,
      dut.\u_dma_u_read_beats_left_reg[1] , dut.\u_dma_u_read_beats_left_reg[0] };
  wire [4:0] trace_burst_beats = {
      dut.\u_dma_u_read_burst_beats_reg[4] , dut.\u_dma_u_read_burst_beats_reg[3] ,
      dut.\u_dma_u_read_burst_beats_reg[2] , dut.\u_dma_u_read_burst_beats_reg[1] ,
      dut.\u_dma_u_read_burst_beats_reg[0] };
  wire [7:0] trace_beat_in_burst = {
      dut.\u_dma_u_read_beat_in_burst_reg[7] , dut.\u_dma_u_read_beat_in_burst_reg[6] ,
      dut.\u_dma_u_read_beat_in_burst_reg[5] , dut.\u_dma_u_read_beat_in_burst_reg[4] ,
      dut.\u_dma_u_read_beat_in_burst_reg[3] , dut.\u_dma_u_read_beat_in_burst_reg[2] ,
      dut.\u_dma_u_read_beat_in_burst_reg[1] , dut.\u_dma_u_read_beat_in_burst_reg[0] };
  wire trace_dma_rd_ready_est =
      ((dut.dma_rd_kind == 2'd0) && dut.q_rd_ready) ||
      ((dut.dma_rd_kind == 2'd1) && dut.k_rd_ready) ||
      ((dut.dma_rd_kind == 2'd2) && dut.v_rd_ready);
  wire [1:0] trace_dma_wr_state = {dut.\u_dma_u_write_state_reg[1] ,
                                   dut.\u_dma_u_write_state_reg[0] };
  wire [15:0] trace_wr_beats_left = {
      dut.\u_dma_u_write_beats_left_reg[15] , dut.\u_dma_u_write_beats_left_reg[14] ,
      dut.\u_dma_u_write_beats_left_reg[13] , dut.\u_dma_u_write_beats_left_reg[12] ,
      dut.\u_dma_u_write_beats_left_reg[11] , dut.\u_dma_u_write_beats_left_reg[10] ,
      dut.\u_dma_u_write_beats_left_reg[9] , dut.\u_dma_u_write_beats_left_reg[8] ,
      dut.\u_dma_u_write_beats_left_reg[7] , dut.\u_dma_u_write_beats_left_reg[6] ,
      dut.\u_dma_u_write_beats_left_reg[5] , dut.\u_dma_u_write_beats_left_reg[4] ,
      dut.\u_dma_u_write_beats_left_reg[3] , dut.\u_dma_u_write_beats_left_reg[2] ,
      dut.\u_dma_u_write_beats_left_reg[1] , dut.\u_dma_u_write_beats_left_reg[0] };
  wire [4:0] trace_wr_burst_beats = {
      dut.\u_dma_u_write_burst_beats_reg[4] , dut.\u_dma_u_write_burst_beats_reg[3] ,
      dut.\u_dma_u_write_burst_beats_reg[2] , dut.\u_dma_u_write_burst_beats_reg[1] ,
      dut.\u_dma_u_write_burst_beats_reg[0] };
  wire [3:0] trace_wr_beat_in_burst = {
      dut.\u_dma_u_write_beat_in_burst_reg[3] , dut.\u_dma_u_write_beat_in_burst_reg[2] ,
      dut.\u_dma_u_write_beat_in_burst_reg[1] , dut.\u_dma_u_write_beat_in_burst_reg[0] };
`endif

  task automatic dump_timeout_diag;
    begin
      $display("DIAG: timeout cycle_count=%0d status=0x%08h irq=%b o_write_beats=%0d o_write_bursts=%0d",
               cycle_count, status, irq, o_write_beats, o_write_bursts);
      $display("DIAG: counts q/k/v/o_start=%0d/%0d/%0d/%0d pm_cmd_valid_cycles=%0d dma_done=%0d rd_done=%0d wr_done=%0d",
               q_start_count, k_start_count, v_start_count, o_start_count,
               pm_cmd_count, dma_done_count, dma_read_done_count, dma_write_done_count);
      $display("DIAG: counts axi ar/r/aw/w/b=%0d/%0d/%0d/%0d/%0d init=%0d score=%0d complete=%0d fin_req=%0d fin_o=%0d fin_done=%0d",
               axi_ar_count, axi_r_count, axi_aw_count, axi_w_count, axi_b_count,
               init_fire_count, score_issue_count, complete_count, fin_req_count,
               fin_o_count, fin_done_count);
      $display("DIAG: AXI ar v/r=%b/%b r v/r/last=%b/%b/%b aw v/r=%b/%b w v/r/last=%b/%b/%b b v/r=%b/%b",
               m_axi_arvalid, m_axi_arready, m_axi_rvalid, m_axi_rready, m_axi_rlast,
               m_axi_awvalid, m_axi_awready, m_axi_wvalid, m_axi_wready, m_axi_wlast,
               m_axi_bvalid, m_axi_bready);
`ifdef FA_GATE_DIAG
      $display("DIAG: dut start=%b init_start=%b run_enable=%b busy=%b done_pulse=%b error=%b regs_done=%b regs_error=%b",
               dut.start_pulse, dut.init_start, dut.run_enable,
               dut.task_busy, dut.task_done_pulse, dut.task_error,
               dut.u_regs_done_latched_reg, dut.u_regs_error_latched_reg);
      $display("DIAG: dut pm_cmd_valid=%b q_ready=%b kv_ready=%b init v/r=%b/%b score v/r=%b/%b complete=%b",
               dut.pm_cmd_valid, dut.q_group_ready, dut.kv_tile_ready,
               dut.init_valid, dut.init_ready, dut.score_valid, dut.score_ready,
               dut.complete_valid);
      $display("DIAG: dut fin_req v/r=%b/%b fin_o v/r=%b/%b fin_done=%b",
               dut.fin_req_valid, dut.fin_req_ready, dut.fin_o_valid,
               dut.fin_o_ready, dut.fin_done_valid);
      $display("DIAG: dut pulses q/k/v/o_start=%b/%b/%b/%b o_busy=%b sched_done=%b pm_done=%b fin_done=%b fin_err_zero_l=%b",
               dut.q_load_start, dut.k_load_start, dut.v_load_start, dut.o_store_start,
               dut.o_store_busy, dut.sched_done, dut.pm_done, dut.fin_done_valid,
               dut.fin_error_zero_l);
      $display("DIAG: dut dma rd_valid=%b wr_valid/ready=%b/%b rd_done/error=%b/%b wr_done/error=%b/%b",
               dut.dma_rd_valid, dut.dma_wr_valid, dut.dma_wr_ready,
               dut.u_dma_rd_done_valid, dut.u_dma_rd_error, dut.u_dma_wr_done_valid,
               dut.u_dma_wr_error);
      $display("DIAG: dma_read state=%b beats_left=%0d burst_beats=%0d beat_in_burst=%0d q_rd_ready=%b q_load_count=%0d",
               {dut.\u_dma_u_read_state_reg[1] , dut.\u_dma_u_read_state_reg[0] },
               {dut.\u_dma_u_read_beats_left_reg[15] , dut.\u_dma_u_read_beats_left_reg[14] ,
                dut.\u_dma_u_read_beats_left_reg[13] , dut.\u_dma_u_read_beats_left_reg[12] ,
                dut.\u_dma_u_read_beats_left_reg[11] , dut.\u_dma_u_read_beats_left_reg[10] ,
                dut.\u_dma_u_read_beats_left_reg[9] , dut.\u_dma_u_read_beats_left_reg[8] ,
                dut.\u_dma_u_read_beats_left_reg[7] , dut.\u_dma_u_read_beats_left_reg[6] ,
                dut.\u_dma_u_read_beats_left_reg[5] , dut.\u_dma_u_read_beats_left_reg[4] ,
                dut.\u_dma_u_read_beats_left_reg[3] , dut.\u_dma_u_read_beats_left_reg[2] ,
                dut.\u_dma_u_read_beats_left_reg[1] , dut.\u_dma_u_read_beats_left_reg[0] },
               {dut.\u_dma_u_read_burst_beats_reg[4] , dut.\u_dma_u_read_burst_beats_reg[3] ,
                dut.\u_dma_u_read_burst_beats_reg[2] , dut.\u_dma_u_read_burst_beats_reg[1] ,
                dut.\u_dma_u_read_burst_beats_reg[0] },
               {dut.\u_dma_u_read_beat_in_burst_reg[7] , dut.\u_dma_u_read_beat_in_burst_reg[6] ,
                dut.\u_dma_u_read_beat_in_burst_reg[5] , dut.\u_dma_u_read_beat_in_burst_reg[4] ,
                dut.\u_dma_u_read_beat_in_burst_reg[3] , dut.\u_dma_u_read_beat_in_burst_reg[2] ,
                dut.\u_dma_u_read_beat_in_burst_reg[1] , dut.\u_dma_u_read_beat_in_burst_reg[0] },
               dut.q_rd_ready, dut.u_q_adapter_q_load_count_reg);
`ifdef FA_GATE_TRACE
      $display("DIAG: dma_write state=%b beats_left=%b burst_beats=%b beat_in_burst=%b wr_valid/ready=%b/%b wlast=%b has_x state/left/burst/beat=%b/%b/%b/%b",
               trace_dma_wr_state, trace_wr_beats_left, trace_wr_burst_beats,
               trace_wr_beat_in_burst, dut.dma_wr_valid, dut.dma_wr_ready,
               m_axi_wlast, $isunknown(trace_dma_wr_state),
               $isunknown(trace_wr_beats_left), $isunknown(trace_wr_burst_beats),
               $isunknown(trace_wr_beat_in_burst));
`endif
`endif
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
      o_write_beats <= 0;
      o_write_bursts <= 0;
      q_start_count <= 0;
      k_start_count <= 0;
      v_start_count <= 0;
      o_start_count <= 0;
      pm_cmd_count <= 0;
      dma_done_count <= 0;
      dma_read_done_count <= 0;
      dma_write_done_count <= 0;
      axi_ar_count <= 0;
      axi_r_count <= 0;
      axi_aw_count <= 0;
      axi_w_count <= 0;
      axi_b_count <= 0;
      init_fire_count <= 0;
      score_issue_count <= 0;
      complete_count <= 0;
      fin_req_count <= 0;
      fin_o_count <= 0;
      fin_done_count <= 0;
      write_is_o_q <= 1'b0;
`ifdef FA_GATE_TRACE
      trace_active <= 1'b0;
      trace_cycles_left <= 0;
      trace_r_handshake_count <= 0;
      trace_write_x_seen <= 1'b0;
      trace_wr_beat_x_seen <= 1'b0;
`endif
    end else begin
      cycle_count <= cycle_count + 1;

`ifdef FA_GATE_DIAG
      if (dut.q_load_start) q_start_count <= q_start_count + 1;
      if (dut.k_load_start) k_start_count <= k_start_count + 1;
      if (dut.v_load_start) v_start_count <= v_start_count + 1;
      if (dut.o_store_start) o_start_count <= o_start_count + 1;
      if (dut.pm_cmd_valid) pm_cmd_count <= pm_cmd_count + 1;
      if (dut.u_dma_rd_done_valid || dut.u_dma_wr_done_valid) begin
        dma_done_count <= dma_done_count + 1;
      end
      if (dut.u_dma_rd_done_valid) begin
        dma_read_done_count <= dma_read_done_count + 1;
      end
      if (dut.u_dma_wr_done_valid) begin
        dma_write_done_count <= dma_write_done_count + 1;
      end
      if (dut.init_valid && dut.init_ready) init_fire_count <= init_fire_count + 1;
      if (dut.score_valid && dut.score_ready) score_issue_count <= score_issue_count + 1;
      if (dut.complete_valid) complete_count <= complete_count + 1;
      if (dut.fin_req_valid && dut.fin_req_ready) fin_req_count <= fin_req_count + 1;
      if (dut.fin_o_valid && dut.fin_o_ready) fin_o_count <= fin_o_count + 1;
      if (dut.fin_done_valid) fin_done_count <= fin_done_count + 1;
`endif

      if (m_axi_arvalid && m_axi_arready) axi_ar_count <= axi_ar_count + 1;
      if (m_axi_rvalid && m_axi_rready) axi_r_count <= axi_r_count + 1;
      if (m_axi_awvalid && m_axi_awready) axi_aw_count <= axi_aw_count + 1;
      if (m_axi_wvalid && m_axi_wready) axi_w_count <= axi_w_count + 1;
      if (m_axi_bvalid && m_axi_bready) axi_b_count <= axi_b_count + 1;

`ifdef FA_GATE_TRACE
      if (!trace_active && (axi_ar_count == 0) && m_axi_arvalid && m_axi_arready) begin
        trace_active <= 1'b1;
        trace_cycles_left <= 160;
        trace_r_handshake_count <= 0;
        $display("TRACE_BEGIN first_ar cyc=%0d time=%0t araddr=0x%016h arlen=%0d arsize=%0d arburst=%0d",
                 cycle_count, $time, m_axi_araddr, m_axi_arlen, m_axi_arsize, m_axi_arburst);
      end else if (trace_active && (trace_cycles_left != 0)) begin
        trace_cycles_left <= trace_cycles_left - 1;
        if (trace_cycles_left == 1) begin
          trace_active <= 1'b0;
          $display("TRACE_END cyc=%0d time=%0t r_hs_total=%0d state=%b beats_left=%0d beat_in_burst=%0d q_load_count=%0d",
                   cycle_count, $time, trace_r_handshake_count, trace_dma_state,
                   trace_beats_left, trace_beat_in_burst, dut.u_q_adapter_q_load_count_reg);
        end
      end

      if (m_axi_rvalid && m_axi_rready) begin
        trace_r_handshake_count <= trace_r_handshake_count + 1;
      end

      if (trace_active ||
          ((axi_ar_count == 0) && m_axi_arvalid && m_axi_arready) ||
          m_axi_rvalid || dut.dma_rd_valid || dut.u_dma_rd_done_valid ||
          m_axi_awvalid || m_axi_wvalid || m_axi_bvalid || dut.dma_wr_valid ||
          dut.u_dma_wr_done_valid) begin
        $display("TRACE cyc=%0d t=%0t ar=%b/%b araddr=0x%016h arlen=%0d r=%b/%b last=%b rresp=%b r_hs=%0d aw=%b/%b awaddr=0x%016h awlen=%0d w=%b/%b wlast=%b b=%b/%b bresp=%b aw_hs=%0d w_hs=%0d b_hs=%0d state=%b beats_left=%0d burst=%0d beat_in_burst=%0d pm_cmd=%b kind=%0d tag=0x%02h dma_rd=%b dma_wr=%b/%b ready_est=%b rd_kind=%0d q/k/v_ready=%b/%b/%b q_start=%b q_count=%0d rd_done=%b rd_err=%b wr_done=%b wr_err=%b",
                 cycle_count, $time,
                 m_axi_arvalid, m_axi_arready, m_axi_araddr, m_axi_arlen,
                 m_axi_rvalid, m_axi_rready, m_axi_rlast, m_axi_rresp,
                 trace_r_handshake_count + ((m_axi_rvalid && m_axi_rready) ? 1 : 0),
                 m_axi_awvalid, m_axi_awready, m_axi_awaddr, m_axi_awlen,
                 m_axi_wvalid, m_axi_wready, m_axi_wlast,
                 m_axi_bvalid, m_axi_bready, m_axi_bresp,
                 axi_aw_count + ((m_axi_awvalid && m_axi_awready) ? 1 : 0),
                 axi_w_count + ((m_axi_wvalid && m_axi_wready) ? 1 : 0),
                 axi_b_count + ((m_axi_bvalid && m_axi_bready) ? 1 : 0),
                 trace_dma_state, trace_beats_left, trace_burst_beats, trace_beat_in_burst,
                 dut.pm_cmd_valid, dut.pm_cmd_kind, dut.pm_cmd_tag,
                 dut.dma_rd_valid, dut.dma_wr_valid, dut.dma_wr_ready,
                 trace_dma_rd_ready_est, dut.dma_rd_kind,
                 dut.q_rd_ready, dut.k_rd_ready, dut.v_rd_ready,
                 dut.q_load_start, dut.u_q_adapter_q_load_count_reg,
                 dut.u_dma_rd_done_valid, dut.u_dma_rd_error,
                 dut.u_dma_wr_done_valid, dut.u_dma_wr_error);
      end

      if (dut.o_store_start || (m_axi_awvalid && m_axi_awready) ||
          (m_axi_wvalid && m_axi_wready) || dut.u_dma_wr_done_valid) begin
        $display("WRTRACE event=%s cyc=%0d t=%0t aw=%b/%b awlen=%0d w=%b/%b wlast=%b w_hs_next=%0d state=%b beats_left=%b burst_beats=%b beat_in_burst=%b has_x state/left/burst/beat=%b/%b/%b/%b dma_wr=%b/%b wr_done=%b wr_err=%b",
                 dut.o_store_start ? "o_start" :
                 ((m_axi_awvalid && m_axi_awready) ? "aw_hs" :
                  ((m_axi_wvalid && m_axi_wready) ? "w_hs" : "wr_done")),
                 cycle_count, $time, m_axi_awvalid, m_axi_awready, m_axi_awlen,
                 m_axi_wvalid, m_axi_wready, m_axi_wlast,
                 axi_w_count + ((m_axi_wvalid && m_axi_wready) ? 1 : 0),
                 trace_dma_wr_state, trace_wr_beats_left, trace_wr_burst_beats,
                 trace_wr_beat_in_burst, $isunknown(trace_dma_wr_state),
                 $isunknown(trace_wr_beats_left), $isunknown(trace_wr_burst_beats),
                 $isunknown(trace_wr_beat_in_burst), dut.dma_wr_valid,
                 dut.dma_wr_ready, dut.u_dma_wr_done_valid, dut.u_dma_wr_error);
      end

      if (!trace_wr_beat_x_seen && (axi_aw_count != 0) &&
          (trace_dma_wr_state != 2'b00) && $isunknown(trace_wr_beat_in_burst)) begin
        trace_wr_beat_x_seen <= 1'b1;
        $display("WRTRACE first_beat_idx_x cyc=%0d t=%0t state=%b beats_left=%b burst_beats=%b beat_in_burst=%b aw_hs=%0d w_hs=%0d w=%b/%b wlast=%b dma_wr=%b/%b",
                 cycle_count, $time, trace_dma_wr_state, trace_wr_beats_left,
                 trace_wr_burst_beats, trace_wr_beat_in_burst, axi_aw_count,
                 axi_w_count, m_axi_wvalid, m_axi_wready, m_axi_wlast,
                 dut.dma_wr_valid, dut.dma_wr_ready);
      end

`ifdef FA_GATE_XTRACE
      if (!trace_write_x_seen && (axi_aw_count != 0) &&
          ($isunknown(m_axi_awvalid) ||
           ((m_axi_awvalid !== 1'b0) &&
            ($isunknown(m_axi_awaddr) || $isunknown(m_axi_awlen) ||
             $isunknown(m_axi_awsize) || $isunknown(m_axi_awburst))) ||
           $isunknown(m_axi_wvalid) ||
           ((m_axi_wvalid !== 1'b0) &&
            ($isunknown(m_axi_wdata) || $isunknown(m_axi_wstrb) ||
             $isunknown(m_axi_wlast))) ||
           $isunknown(m_axi_bready) ||
           $isunknown(dut.dma_wr_valid) || $isunknown(dut.dma_wr_ready) ||
           $isunknown(dut.o_store_busy) || $isunknown(dut.u_dma_wr_done_valid) ||
           $isunknown(dut.u_dma_wr_error))) begin
        trace_write_x_seen <= 1'b1;
        $display("XTRACE first_write_x cyc=%0d t=%0t status=0x%08h irq=%b counts ar/r/aw/w/b=%0d/%0d/%0d/%0d/%0d",
                 cycle_count, $time, status, irq,
                 axi_ar_count, axi_r_count, axi_aw_count, axi_w_count, axi_b_count);
        $display("XTRACE axi aw=%b/%b awaddr=0x%016h awlen=%b awsize=%b awburst=%b w=%b/%b wlast=%b wstrb=0x%04h wdata_has_x=%b b=%b/%b bresp=%b",
                 m_axi_awvalid, m_axi_awready, m_axi_awaddr, m_axi_awlen,
                 m_axi_awsize, m_axi_awburst, m_axi_wvalid, m_axi_wready,
                 m_axi_wlast, m_axi_wstrb, $isunknown(m_axi_wdata),
                 m_axi_bvalid, m_axi_bready, m_axi_bresp);
        $display("XTRACE dut o_start=%b o_busy=%b dma_wr=%b/%b wr_done=%b wr_err=%b pm_done=%b sched_done=%b fin_done=%b task_busy=%b task_done=%b task_error=%b",
                 dut.o_store_start, dut.o_store_busy, dut.dma_wr_valid,
                 dut.dma_wr_ready, dut.u_dma_wr_done_valid, dut.u_dma_wr_error,
                 dut.pm_done, dut.sched_done, dut.fin_done_valid,
                 dut.task_busy, dut.task_done_pulse, dut.task_error);
        $display("XTRACE dma_write state=%b beats_left=%b burst_beats=%b beat_in_burst=%b has_x state/left/burst/beat=%b/%b/%b/%b",
                 trace_dma_wr_state, trace_wr_beats_left, trace_wr_burst_beats,
                 trace_wr_beat_in_burst, $isunknown(trace_dma_wr_state),
                 $isunknown(trace_wr_beats_left), $isunknown(trace_wr_burst_beats),
                 $isunknown(trace_wr_beat_in_burst));
        dump_timeout_diag();
`ifdef FA_GATE_XSTOP
        fail("XTRACE write path became unknown");
`endif
      end
`endif
`endif

      if (cycle_count > MAX_CYCLES) begin
        dump_timeout_diag();
        fail("timeout waiting for S256 zero run to complete");
      end

      if (m_axi_awvalid && m_axi_awready) begin
        write_is_o_q <= (m_axi_awaddr >= O_BASE) && (m_axi_awaddr < O_LIMIT);
        if ((m_axi_awaddr >= O_BASE) && (m_axi_awaddr < O_LIMIT)) begin
          o_write_bursts <= o_write_bursts + 1;
          if (m_axi_awsize !== 3'd4) fail("O write AWSIZE is not 128-bit");
          if (m_axi_awburst !== 2'b01) fail("O write AWBURST is not INCR");
        end
      end

      if (m_axi_wvalid && m_axi_wready && write_is_o_q) begin
        o_write_beats <= o_write_beats + 1;
        if (m_axi_wstrb !== 16'hffff) fail("O write WSTRB is not full width");
        if (m_axi_wdata !== 128'd0) fail("zero-input O write data is nonzero");
      end
    end
  end

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

    if (status[2]) fail("S256 zero run completed with STATUS.ERROR");
    if (!irq) fail("IRQ did not assert after DONE with IRQ_EN=1");

    axil_read(REG_CYCLES, cycles_reg);
    if (o_write_beats != EXPECTED_O_BEATS) begin
      $display("FAIL: O write beats got=%0d exp=%0d bursts=%0d cycles=%0d",
               o_write_beats, EXPECTED_O_BEATS, o_write_bursts, cycles_reg);
      $fatal(1);
    end

    $display("PASS: fa_top S256 zero run cycles=%0d o_write_beats=%0d o_write_bursts=%0d",
             cycles_reg, o_write_beats, o_write_bursts);
    $finish;
  end
endmodule
