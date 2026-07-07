`timescale 1ns/1ps

module tb_fa_top;

  localparam S = 256;
  localparam D = 64;
  localparam ELEM_W = 16;
  localparam AXI_DATA_W = 128;
  localparam AXI_STRB_W = AXI_DATA_W / 8;
  localparam BYTES_PER_ROW = D * 2;        // 128 bytes
  localparam MATRIX_BYTES = S * BYTES_PER_ROW; // 32768 bytes
  localparam MEM_SIZE = 256 * 1024;        // 256 KB memory model

  logic clk, rst_n;

  // AXI4-Lite
  logic [11:0]  s_axil_awaddr;
  logic         s_axil_awvalid, s_axil_awready;
  logic [31:0]  s_axil_wdata;
  logic [3:0]   s_axil_wstrb;
  logic         s_axil_wvalid, s_axil_wready;
  logic [1:0]   s_axil_bresp;
  logic         s_axil_bvalid, s_axil_bready;
  logic [11:0]  s_axil_araddr;
  logic         s_axil_arvalid, s_axil_arready;
  logic [31:0]  s_axil_rdata;
  logic [1:0]   s_axil_rresp;
  logic         s_axil_rvalid, s_axil_rready;

  // AXI4 Master Read (128-bit)
  logic [63:0]  m_axi_araddr;
  logic [7:0]   m_axi_arlen;
  logic [2:0]   m_axi_arsize;
  logic [1:0]   m_axi_arburst;
  logic         m_axi_arvalid, m_axi_arready;
  logic [AXI_DATA_W-1:0] m_axi_rdata;
  logic [1:0]   m_axi_rresp;
  logic         m_axi_rlast, m_axi_rvalid, m_axi_rready;

  // AXI4 Master Write (128-bit)
  logic [63:0]  m_axi_awaddr;
  logic [7:0]   m_axi_awlen;
  logic [2:0]   m_axi_awsize;
  logic [1:0]   m_axi_awburst;
  logic         m_axi_awvalid, m_axi_awready;
  logic [AXI_DATA_W-1:0] m_axi_wdata;
  logic [AXI_STRB_W-1:0] m_axi_wstrb;
  logic         m_axi_wlast, m_axi_wvalid, m_axi_wready;
  logic [1:0]   m_axi_bresp;
  logic         m_axi_bvalid, m_axi_bready;

  logic         irq;

  // Memory model
  logic [7:0]   mem [0:MEM_SIZE-1];

  // Flat arrays for Q/K/V loading
  logic [ELEM_W-1:0] q_flat [0:S*D-1];
  logic [ELEM_W-1:0] k_flat [0:S*D-1];
  logic [ELEM_W-1:0] v_flat [0:S*D-1];

  // O data captured from DMA writes
  logic [ELEM_W-1:0] o_captured [0:S*D-1];
  logic [S*D-1:0]    o_captured_mask;  // which elements were written

  // =============================================================
  //  DUT
  // =============================================================
  fa_top u_dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr,  .s_axil_awvalid, .s_axil_awready,
    .s_axil_wdata,   .s_axil_wstrb,   .s_axil_wvalid, .s_axil_wready,
    .s_axil_bresp,   .s_axil_bvalid,  .s_axil_bready,
    .s_axil_araddr,  .s_axil_arvalid, .s_axil_arready,
    .s_axil_rdata,   .s_axil_rresp,   .s_axil_rvalid, .s_axil_rready,
    .m_axi_araddr,  .m_axi_arlen,  .m_axi_arsize,  .m_axi_arburst,
    .m_axi_arvalid, .m_axi_arready, .m_axi_rdata,   .m_axi_rresp,
    .m_axi_rlast,   .m_axi_rvalid, .m_axi_rready,
    .m_axi_awaddr,  .m_axi_awlen,  .m_axi_awsize,  .m_axi_awburst,
    .m_axi_awvalid, .m_axi_awready, .m_axi_wdata,   .m_axi_wstrb,
    .m_axi_wlast,   .m_axi_wvalid, .m_axi_wready,
    .m_axi_bresp,   .m_axi_bvalid, .m_axi_bready,
    .irq(irq),
    // AXI4-Stream ports (unused in DMA mode)
    .s_axis_tvalid(1'b0),
    .s_axis_tready(),
    .s_axis_tdata(128'd0),
    .s_axis_tkeep(16'd0),
    .s_axis_tuser(2'd0),
    .s_axis_tlast(1'b0),
    .m_axis_tvalid(),
    .m_axis_tready(1'b0),
    .m_axis_tdata(),
    .m_axis_tkeep(),
    .m_axis_tlast()
  );

  // =============================================================
  //  X-propag assertion: detect beat_in_burst_reg X in dma_write_master
  // =============================================================
  wire [4:0] beat_in_burst_sig = u_dut.u_dma.u_write.beat_in_burst_reg;
  wire       wlast_sig         = u_dut.u_dma.u_write.m_axi_wlast_reg;

  always @(posedge clk) begin
    if (rst_n) begin
      if (^beat_in_burst_sig === 1'bx) begin
        $display("[%0t] ASSERT FAIL: beat_in_burst_reg has X! value=%b", $time, beat_in_burst_sig);
        $finish;
      end
      if (^wlast_sig === 1'bx) begin
        $display("[%0t] ASSERT FAIL: m_axi_wlast_reg has X! value=%b", $time, wlast_sig);
        $finish;
      end
    end
  end

  // Check m_axi_wlast output never X
  always @(posedge clk) begin
    if (rst_n && m_axi_wvalid) begin
      if (^m_axi_wlast === 1'bx) begin
        $display("[%0t] ASSERT FAIL: m_axi_wlast is X while wvalid=1!", $time);
        $finish;
      end
    end
  end

  // =============================================================
  //  Clock & reset
  // =============================================================
  initial begin
    $display("[%0t] Simulation started", $time);
  end

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    #20 rst_n = 1;
  end

  // =============================================================
  //  AXI4 bus activity monitor (debug)
  // =============================================================
  integer ar_cnt, aw_cnt, wbeat_cnt;
  initial begin
    ar_cnt = 0; aw_cnt = 0; wbeat_cnt = 0;
    repeat (100) @(posedge clk);
    repeat (5000) begin
      repeat (1000) @(posedge clk);
      $display("[%0t] AXI4: arcnt=%0d(rd_act=%0d rcnt=%0d/%0d) awcnt=%0d(wr_act=%0d wcnt=%0d/%0d wbeat=%0d)",
               $time, ar_cnt, rd_active, rd_cnt, rd_len,
               aw_cnt, wr_active, wr_cnt, wr_len, wbeat_cnt);
    end
  end
  always @(posedge clk) begin
    if (m_axi_arvalid && m_axi_arready) ar_cnt = ar_cnt + 1;
    if (m_axi_awvalid && m_axi_awready) aw_cnt = aw_cnt + 1;
    if (m_axi_wvalid && m_axi_wready) begin
      wbeat_cnt = wbeat_cnt + 1;
      if (m_axi_wlast)
        $display("[%0t] *** WLAST beat %0d: wcnt=%0d/%0d awcnt=%0d",
                 $time, wbeat_cnt, wr_cnt, wr_len, aw_cnt);
    end
  end

  integer last_wbeat_cycle, stuck_reported;
  initial begin
    last_wbeat_cycle = 0;
    stuck_reported = 0;
    repeat (200) @(posedge clk);
    forever begin
      @(posedge clk);
      if (m_axi_wvalid && m_axi_wready)
        last_wbeat_cycle = $time;
      if (wbeat_cnt > 48 && ($time - last_wbeat_cycle) > 500000 && !stuck_reported) begin
        $display("[%0t] *** STUCK: no W beat for %0d cycles. wbeat=%0d",
                 $time, $time - last_wbeat_cycle, wbeat_cnt);
        stuck_reported = 1;
      end
    end
  end

  // =============================================================
  //  AXI4 Slave Memory Model (128-bit data)
  // =============================================================
  // Read channel state
  logic [63:0]  rd_addr;
  logic [7:0]   rd_len;
  logic [7:0]   rd_cnt;
  logic         rd_active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axi_arready <= 1'b0;
      m_axi_rvalid  <= 1'b0;
      m_axi_rdata   <= '0;
      m_axi_rresp   <= 2'b00;
      m_axi_rlast   <= 1'b0;
      rd_addr   <= '0;
      rd_len    <= '0;
      rd_cnt    <= '0;
      rd_active <= 1'b0;
    end else begin
      // AR handshake
      if (!rd_active && m_axi_arvalid) begin
        m_axi_arready <= 1'b1;
        rd_addr   <= m_axi_araddr;
        rd_len    <= m_axi_arlen;
        rd_cnt    <= '0;
        rd_active <= 1'b1;
      end else if (m_axi_arvalid && m_axi_arready) begin
        m_axi_arready <= 1'b0;
      end

      // R channel — fix: update rdata every beat, not just the first
      if (rd_active) begin
        if (!m_axi_rvalid) begin
          // Send new beat
          m_axi_rvalid <= 1'b1;
          for (int b = 0; b < 16; b++)
            m_axi_rdata[b*8 +: 8] <= mem[rd_addr + rd_cnt * 16 + b];
          m_axi_rlast <= (rd_cnt == rd_len);
          m_axi_rresp <= 2'b00;
        end else if (m_axi_rready) begin
          // Current beat accepted by master
          if (rd_cnt == rd_len) begin
            // Last beat done
            m_axi_rvalid <= 1'b0;
            m_axi_rlast  <= 1'b0;
            rd_active    <= 1'b0;
          end else begin
            // Advance and prepare next beat
            rd_cnt <= rd_cnt + 8'd1;
            for (int b = 0; b < 16; b++)
              m_axi_rdata[b*8 +: 8] <= mem[rd_addr + (rd_cnt + 8'd1) * 16 + b];
            m_axi_rlast <= (rd_cnt + 8'd1 == rd_len);
          end
        end
      end
    end
  end

  // Write channel state
  logic [63:0]  wr_addr;
  logic [7:0]   wr_len;
  logic [7:0]   wr_cnt;
  logic         wr_active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axi_awready <= 1'b0;
      m_axi_wready  <= 1'b0;
      m_axi_bvalid  <= 1'b0;
      m_axi_bresp   <= 2'b00;
      wr_addr   <= '0;
      wr_len    <= '0;
      wr_cnt    <= '0;
      wr_active <= 1'b0;
    end else begin
      // AW handshake
      if (!wr_active && m_axi_awvalid) begin
        m_axi_awready <= 1'b1;
        wr_addr   <= m_axi_awaddr;
        wr_len    <= m_axi_awlen;
        wr_cnt    <= '0;
        wr_active <= 1'b1;
      end else if (m_axi_awvalid && m_axi_awready) begin
        m_axi_awready <= 1'b0;
      end

      // W channel
      if (wr_active) begin
        m_axi_wready <= 1'b1;
        if (m_axi_wvalid && m_axi_wready) begin
          // Write 16 bytes to memory
          for (int b = 0; b < 16; b++) begin
            if (m_axi_wstrb[b])
              mem[wr_addr + wr_cnt * 16 + b] <= m_axi_wdata[b*8 +: 8];
          end
          wr_cnt <= wr_cnt + 8'd1;
          if (m_axi_wlast) begin
            m_axi_wready <= 1'b0;
            // Send B response
            m_axi_bvalid <= 1'b1;
            m_axi_bresp  <= 2'b00;
            wr_active    <= 1'b0;
          end
        end
      end

      // B handshake
      if (m_axi_bvalid && m_axi_bready) begin
        m_axi_bvalid <= 1'b0;
      end
    end
  end

  // =============================================================
  //  Load Q/K/V test vectors into memory (inline to work around
  //  iverilog's lack of unpacked-array task-port support)
  // =============================================================
  integer row, col, idx;
  reg [63:0] byte_addr;

  // =============================================================
  //  AXI4-Lite driver
  // =============================================================
  task axi_write(input logic [11:0] addr, input logic [31:0] data);
    s_axil_awaddr  <= addr;
    s_axil_awvalid <= 1'b1;
    s_axil_wdata   <= data;
    s_axil_wstrb   <= 4'hF;
    s_axil_wvalid  <= 1'b0;  // W valid only after AW handshake
    s_axil_bready  <= 1'b0;
    @(posedge clk);
    // Phase 1: AW handshake
    while (!s_axil_awready) @(posedge clk);
    s_axil_awvalid <= 1'b0;
    // Phase 2: W handshake (aw_hold_reg is now 1, so wready should be 1)
    s_axil_wvalid  <= 1'b1;
    while (!s_axil_wready) @(posedge clk);
    s_axil_wvalid  <= 1'b0;
    // Phase 3: B response
    s_axil_bready  <= 1'b1;
    while (!s_axil_bvalid) @(posedge clk);
    s_axil_bready  <= 1'b0;
    @(posedge clk);
  endtask

  task axi_read(input logic [11:0] addr, output logic [31:0] data);
    s_axil_araddr  <= addr;
    s_axil_arvalid <= 1'b1;
    s_axil_rready  <= 1'b1;
    @(posedge clk);
    while (!s_axil_arready) @(posedge clk);
    s_axil_arvalid <= 1'b0;
    while (!s_axil_rvalid) @(posedge clk);
    data = s_axil_rdata;
    s_axil_rready  <= 1'b0;
    @(posedge clk);
  endtask

  // =============================================================
  //  Register definitions
  // =============================================================
  localparam [11:0] REG_CTRL     = 12'h000;
  localparam [11:0] REG_STATUS   = 12'h004;
  localparam [11:0] REG_CFG      = 12'h008;
  localparam [11:0] REG_Q_BASE_L = 12'h014;
  localparam [11:0] REG_Q_BASE_H = 12'h018;
  localparam [11:0] REG_K_BASE_L = 12'h01C;
  localparam [11:0] REG_K_BASE_H = 12'h020;
  localparam [11:0] REG_V_BASE_L = 12'h024;
  localparam [11:0] REG_V_BASE_H = 12'h028;
  localparam [11:0] REG_O_BASE_L = 12'h02C;
  localparam [11:0] REG_O_BASE_H = 12'h030;
  localparam [11:0] REG_STRIDE   = 12'h034;
  localparam [11:0] REG_NEG_LARGE= 12'h038;
  localparam [11:0] REG_SCALE    = 12'h03C;
  localparam [11:0] REG_CYCLES   = 12'h040;

  // =============================================================
  //  Main test
  // =============================================================
  logic [31:0] rdata;
  integer      start_cycle, end_cycle;
  integer      fd, i;

  // Q/K/V base addresses in memory model
  localparam [63:0] Q_BASE = 64'h0000_0000_0000_0000;
  localparam [63:0] K_BASE = 64'h0000_0000_0001_0000;  // 64KB offset
  localparam [63:0] V_BASE = 64'h0000_0000_0002_0000;  // 128KB offset
  localparam [63:0] O_BASE = 64'h0000_0000_0003_0000;  // 192KB offset

  initial begin
    s_axil_awaddr  = 12'h0;
    s_axil_awvalid = 1'b0;
    s_axil_wdata   = 32'h0;
    s_axil_wstrb   = 4'h0;
    s_axil_wvalid  = 1'b0;
    s_axil_bready  = 1'b0;
    s_axil_araddr  = 12'h0;
    s_axil_arvalid = 1'b0;
    s_axil_rready  = 1'b0;

    // Wait for reset
    repeat (10) @(posedge clk);

    // Load test vectors (inline loops: iverilog doesn't support unpacked-array task args)
    $display("[%0t] Loading Q/K/V test vectors...", $time);
    $readmemh("sim/q_tb.hex", q_flat);
    for (row = 0; row < S; row++) begin
      for (col = 0; col < D; col++) begin
        idx = row * D + col;
        byte_addr = Q_BASE + row * BYTES_PER_ROW + col * 2;
        {mem[byte_addr+1], mem[byte_addr]} = q_flat[idx];
      end
    end
    $readmemh("sim/k_tb.hex", k_flat);
    for (row = 0; row < S; row++) begin
      for (col = 0; col < D; col++) begin
        idx = row * D + col;
        byte_addr = K_BASE + row * BYTES_PER_ROW + col * 2;
        {mem[byte_addr+1], mem[byte_addr]} = k_flat[idx];
      end
    end
    $readmemh("sim/v_tb.hex", v_flat);
    for (row = 0; row < S; row++) begin
      for (col = 0; col < D; col++) begin
        idx = row * D + col;
        byte_addr = V_BASE + row * BYTES_PER_ROW + col * 2;
        {mem[byte_addr+1], mem[byte_addr]} = v_flat[idx];
      end
    end
    $display("[%0t] Q/K/V loaded into memory model.", $time);

    // Configure registers
    $display("[%0t] Configuring registers...", $time);
    axi_write(REG_Q_BASE_L, Q_BASE[31:0]);
    axi_write(REG_Q_BASE_H, Q_BASE[63:32]);
    axi_write(REG_K_BASE_L, K_BASE[31:0]);
    axi_write(REG_K_BASE_H, K_BASE[63:32]);
    axi_write(REG_V_BASE_L, V_BASE[31:0]);
    axi_write(REG_V_BASE_H, V_BASE[63:32]);
    axi_write(REG_O_BASE_L, O_BASE[31:0]);
    axi_write(REG_O_BASE_H, O_BASE[63:32]);
    axi_write(REG_CFG, 32'h1);  // CAUSAL_EN = 1

    // Verify register reads
    axi_read(REG_CFG, rdata);
    $display("[%0t] CFG = 0x%08h", $time, rdata);
    axi_read(REG_STATUS, rdata);
    $display("[%0t] STATUS = 0x%08h", $time, rdata);

    // Start
    $display("[%0t] Starting FlashAttention...", $time);
    start_cycle = $time / 10;
    axi_write(REG_CTRL, 32'h1);

    // Wait for DONE — poll with progress prints
    repeat (5) @(posedge clk);
    do begin
      @(posedge clk);
      // Poll STATUS every 1000 cycles (10us)
      for (int poll_i = 0; poll_i < 10 && !rdata[1] && !rdata[2]; poll_i++) begin
        repeat (1000) @(posedge clk);
        axi_read(REG_STATUS, rdata);
        $display("[%0t] STATUS = 0x%08h (busy=%0d done=%0d error=%0d)",
                 $time, rdata, rdata[0], rdata[1], rdata[2]);
      end
    end while (!rdata[1] && !rdata[2]);

    end_cycle = $time / 10;
    $display("[%0t] DONE! Cycles: %0d", $time, end_cycle - start_cycle);

    // Read cycle counter
    axi_read(REG_CYCLES, rdata);
    $display("  Hardware cycles: %0d", rdata);

    // Read O from memory (inline: iverilog doesn't support unpacked-array task args)
    $display("  Reading O output from memory...");
    for (row = 0; row < S; row++) begin
      for (col = 0; col < D; col++) begin
        idx = row * D + col;
        byte_addr = O_BASE + row * BYTES_PER_ROW + col * 2;
        o_captured[idx] = {mem[byte_addr+1], mem[byte_addr]};
      end
    end

    // Dump O to hex
    fd = $fopen("sim/o_tb.hex", "w");
    if (fd) begin
      for (i = 0; i < S * D; i++)
        $fwrite(fd, "%04h\n", o_captured[i]);
      $fclose(fd);
      $display("  o_tb.hex written (%0d entries).", S * D);
    end else begin
      $display("  ERROR: Cannot write o_tb.hex");
    end

    // Print some samples
    $display("  o[0..3] = %h %h %h %h",
      o_captured[0], o_captured[1], o_captured[2], o_captured[3]);
    $display("  o[last-3..last] = %h %h %h %h",
      o_captured[S*D-4], o_captured[S*D-3], o_captured[S*D-2], o_captured[S*D-1]);

    $display("[%0t] Test done.", $time);
    #100 $finish;
  end

  // =============================================================
  //  Timeout for debug
  // =============================================================
  initial begin
    #500000000;  // 500ms simulated timeout (safety net)
    $finish;
  end

endmodule
