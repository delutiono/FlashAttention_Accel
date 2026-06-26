`timescale 1ns/1ps

import fa_pkg::*;

module fa_accel_top #(
  parameter int unsigned COMPUTE_ROWS = FA_S,
  parameter int unsigned KV_TILE_ROWS = 64
) (
  input  logic                     clk,
  input  logic                     rst_n,

  input  logic [11:0]              s_axil_awaddr,
  input  logic                     s_axil_awvalid,
  output logic                     s_axil_awready,
  input  logic [31:0]              s_axil_wdata,
  input  logic [3:0]               s_axil_wstrb,
  input  logic                     s_axil_wvalid,
  output logic                     s_axil_wready,
  output logic [1:0]               s_axil_bresp,
  output logic                     s_axil_bvalid,
  input  logic                     s_axil_bready,
  input  logic [11:0]              s_axil_araddr,
  input  logic                     s_axil_arvalid,
  output logic                     s_axil_arready,
  output logic [31:0]              s_axil_rdata,
  output logic [1:0]               s_axil_rresp,
  output logic                     s_axil_rvalid,
  input  logic                     s_axil_rready,

  output logic [FA_ADDR_W-1:0]     m_axi_araddr,
  output logic [7:0]               m_axi_arlen,
  output logic [2:0]               m_axi_arsize,
  output logic [1:0]               m_axi_arburst,
  output logic                     m_axi_arvalid,
  input  logic                     m_axi_arready,
  input  logic [FA_AXI_DATA_W-1:0] m_axi_rdata,
  input  logic [1:0]               m_axi_rresp,
  input  logic                     m_axi_rlast,
  input  logic                     m_axi_rvalid,
  output logic                     m_axi_rready,

  output logic [FA_ADDR_W-1:0]     m_axi_awaddr,
  output logic [7:0]               m_axi_awlen,
  output logic [2:0]               m_axi_awsize,
  output logic [1:0]               m_axi_awburst,
  output logic                     m_axi_awvalid,
  input  logic                     m_axi_awready,
  output logic [FA_AXI_DATA_W-1:0] m_axi_wdata,
  output logic [FA_AXI_STRB_W-1:0] m_axi_wstrb,
  output logic                     m_axi_wlast,
  output logic                     m_axi_wvalid,
  input  logic                     m_axi_wready,
  input  logic [1:0]               m_axi_bresp,
  input  logic                     m_axi_bvalid,
  output logic                     m_axi_bready,

  output logic                     irq
);
  localparam int unsigned TOP_COMPUTE_D = 64;
  localparam int unsigned TOP_AXI_LANES = FA_AXI_DATA_W / FA_ELEM_W;
  localparam int unsigned TOP_ROW_BEATS = TOP_COMPUTE_D / TOP_AXI_LANES;
  localparam int unsigned TOP_ROW_BEAT_IDX_W = $clog2(TOP_ROW_BEATS);
  localparam logic [7:0] TOP_COMPUTE_LAST_ROW = COMPUTE_ROWS - 1;
  localparam logic [7:0] TOP_KV_TILE_LAST_OFFSET = KV_TILE_ROWS - 1;

  logic        start_pulse;
  logic        soft_reset_pulse;
  logic        irq_en;
  logic        causal_en;
  logic        compute_smoke_en;
  logic [63:0] q_base;
  logic [63:0] k_base;
  logic [63:0] v_base;
  logic [63:0] o_base;
  logic [31:0] stride_bytes;
  logic [15:0] neg_large;
  logic [15:0] scale;
  logic [31:0] cycles;
  logic        busy;
  logic        done;
  logic        done_clear;
  logic        error;
  logic        dma_rst_n;

  logic        rd_cmd_valid;
  logic        rd_cmd_ready;
  logic [63:0] rd_cmd_addr;
  logic [63:0] rd_data;
  logic        rd_valid;
  logic        rd_out_ready;
  logic        rd_last;
  logic        rd_done;
  logic        rd_error;
  logic [31:0] rd_byte_count;

  logic        wr_cmd_valid;
  logic        wr_cmd_ready;
  logic [63:0] wr_cmd_addr;
  logic [63:0] wr_in_data;
  logic        wr_in_valid;
  logic        wr_in_ready;
  logic        wr_in_last;
  logic        wr_done;
  logic        wr_error;
  logic [31:0] wr_byte_count;

  logic signed [FA_ELEM_W-1:0] compute_q_row [TOP_COMPUTE_D];
  logic signed [FA_ELEM_W-1:0] compute_k_row [TOP_COMPUTE_D];
  logic signed [FA_ELEM_W-1:0] compute_v_row [TOP_COMPUTE_D];
  logic signed [FA_ELEM_W-1:0] compute_o_row [TOP_COMPUTE_D];

  logic        row_engine_valid_i;
  logic        row_engine_row_start;
  logic        row_engine_last;
  logic        row_engine_ready;
  logic        row_engine_busy;
  logic        row_engine_valid_o;
  logic        row_engine_div_zero;
  logic signed [FA_ELEM_W-1:0] row_engine_o [TOP_COMPUTE_D];

  typedef enum logic [4:0] {
    TOP_ST_IDLE,
    TOP_ST_DMA_ISSUE,
    TOP_ST_DMA_RUN,
    TOP_ST_DMA_COMPLETE,
    TOP_ST_COMPUTE_LOAD_Q_ISSUE,
    TOP_ST_COMPUTE_LOAD_Q_RUN,
    TOP_ST_COMPUTE_LOAD_K_ISSUE,
    TOP_ST_COMPUTE_LOAD_K_RUN,
    TOP_ST_COMPUTE_LOAD_V_ISSUE,
    TOP_ST_COMPUTE_LOAD_V_RUN,
    TOP_ST_COMPUTE_ENGINE_ISSUE,
    TOP_ST_COMPUTE_ENGINE_WAIT,
    TOP_ST_COMPUTE_WRITE_ISSUE,
    TOP_ST_COMPUTE_WRITE_RUN,
    TOP_ST_COMPUTE_COMPLETE
  } top_state_e;

  top_state_e top_state;
  logic       top_dma_smoke_rd_issued;
  logic       top_dma_smoke_wr_issued;
  logic       top_dma_smoke_rd_done_seen;
  logic       top_dma_smoke_wr_done_seen;
  logic [7:0] compute_q_idx;
  logic [7:0] compute_kv_tile_base_idx;
  logic [7:0] compute_key_in_tile_idx;
  logic [7:0] compute_k_idx;
  logic [TOP_ROW_BEAT_IDX_W-1:0] compute_rd_beat_idx;
  logic [TOP_ROW_BEAT_IDX_W-1:0] compute_wr_beat_idx;
  logic [63:0] compute_rd_addr;
  logic [63:0] compute_wr_data;
  logic [7:0]  compute_row_last_key_idx;
  logic        compute_key_is_row_last;
  logic        compute_key_is_tile_last;

  function automatic logic [63:0] top_row_addr(
    input logic [63:0] base,
    input logic [7:0]  row
  );
    logic [63:0] row_ext;
    logic [63:0] stride_ext;
    begin
      row_ext = {56'h0, row};
      stride_ext = {32'h0, stride_bytes};
      top_row_addr = base + (row_ext * stride_ext);
    end
  endfunction

  fa_regfile u_regfile (
    .clk              (clk),
    .rst_n            (rst_n),
    .s_axil_awaddr    (s_axil_awaddr),
    .s_axil_awvalid   (s_axil_awvalid),
    .s_axil_awready   (s_axil_awready),
    .s_axil_wdata     (s_axil_wdata),
    .s_axil_wstrb     (s_axil_wstrb),
    .s_axil_wvalid    (s_axil_wvalid),
    .s_axil_wready    (s_axil_wready),
    .s_axil_bresp     (s_axil_bresp),
    .s_axil_bvalid    (s_axil_bvalid),
    .s_axil_bready    (s_axil_bready),
    .s_axil_araddr    (s_axil_araddr),
    .s_axil_arvalid   (s_axil_arvalid),
    .s_axil_arready   (s_axil_arready),
    .s_axil_rdata     (s_axil_rdata),
    .s_axil_rresp     (s_axil_rresp),
    .s_axil_rvalid    (s_axil_rvalid),
    .s_axil_rready    (s_axil_rready),
    .start_pulse      (start_pulse),
    .soft_reset_pulse (soft_reset_pulse),
    .done_clear_pulse (done_clear),
    .irq_en           (irq_en),
    .causal_en        (causal_en),
    .compute_smoke_en (compute_smoke_en),
    .q_base           (q_base),
    .k_base           (k_base),
    .v_base           (v_base),
    .o_base           (o_base),
    .stride_bytes     (stride_bytes),
    .neg_large        (neg_large),
    .scale            (scale),
    .cycles_i         (cycles),
    .busy_i           (busy),
    .done_i           (done),
    .error_i          (error)
  );

  fa_scheduler u_scheduler (
    .clk              (clk),
    .rst_n            (rst_n),
    .start_i          (1'b0),
    .soft_reset_i     (soft_reset_pulse),
    .done_clear_i     (done_clear),
    .causal_en_i      (causal_en),
    .q_base_i         (q_base),
    .k_base_i         (k_base),
    .v_base_i         (v_base),
    .o_base_i         (o_base),
    .stride_bytes_i   (stride_bytes),
    .neg_large_i      (neg_large),
    .scale_i          (scale),
    .busy_o           (),
    .done_o           (),
    .error_o          (),
    .cycles_o         (),
    .state_o          (),
    .q_index_o        (),
    .kv_tile_o        (),
    .k_index_o        (),
    .score_valid_o    ()
  );

  fa_row_engine #(
    .D(TOP_COMPUTE_D),
    .ELEM_W(FA_ELEM_W),
    .OUT_W(FA_ELEM_W)
  ) u_row_engine (
    .clk,
    .rst_n             (dma_rst_n),
    .valid_i           (row_engine_valid_i),
    .row_start_i       (row_engine_row_start),
    .last_i            (row_engine_last),
    .q_index_i         (compute_q_idx),
    .k_index_i         (compute_k_idx),
    .q_i               (compute_q_row),
    .k_i               (compute_k_row),
    .v_i               (compute_v_row),
    .ready_o           (row_engine_ready),
    .busy_o            (row_engine_busy),
    .valid_o           (row_engine_valid_o),
    .div_zero_o        (row_engine_div_zero),
    .o_q88_o           (row_engine_o)
  );

  assign dma_rst_n = rst_n & !soft_reset_pulse;
  assign irq       = irq_en & done;

  always_comb begin
    compute_rd_addr = 64'h0;
    unique case (top_state)
      TOP_ST_COMPUTE_LOAD_Q_ISSUE,
      TOP_ST_COMPUTE_LOAD_Q_RUN: compute_rd_addr = top_row_addr(q_base, compute_q_idx);
      TOP_ST_COMPUTE_LOAD_K_ISSUE,
      TOP_ST_COMPUTE_LOAD_K_RUN: compute_rd_addr = top_row_addr(k_base, compute_k_idx);
      TOP_ST_COMPUTE_LOAD_V_ISSUE,
      TOP_ST_COMPUTE_LOAD_V_RUN: compute_rd_addr = top_row_addr(v_base, compute_k_idx);
      default: compute_rd_addr = q_base;
    endcase
  end

  always_comb begin
    compute_wr_data = 64'h0;
    for (int lane = 0; lane < TOP_AXI_LANES; lane++) begin
      compute_wr_data[(lane * 16) +: 16] =
          compute_o_row[(compute_wr_beat_idx * TOP_AXI_LANES) + lane];
    end
  end

  assign rd_cmd_valid = (top_state == TOP_ST_DMA_ISSUE &&
                         !top_dma_smoke_rd_issued) ||
                        (top_state == TOP_ST_COMPUTE_LOAD_Q_ISSUE) ||
                        (top_state == TOP_ST_COMPUTE_LOAD_K_ISSUE) ||
                        (top_state == TOP_ST_COMPUTE_LOAD_V_ISSUE);
  assign rd_cmd_addr  = ((top_state == TOP_ST_COMPUTE_LOAD_Q_ISSUE) ||
                         (top_state == TOP_ST_COMPUTE_LOAD_K_ISSUE) ||
                         (top_state == TOP_ST_COMPUTE_LOAD_V_ISSUE)) ?
                        compute_rd_addr : q_base;
  assign rd_out_ready = ((top_state == TOP_ST_COMPUTE_LOAD_Q_RUN) ||
                         (top_state == TOP_ST_COMPUTE_LOAD_K_RUN) ||
                         (top_state == TOP_ST_COMPUTE_LOAD_V_RUN)) ?
                        1'b1 : wr_in_ready;

  assign wr_cmd_valid = (top_state == TOP_ST_DMA_ISSUE &&
                         !top_dma_smoke_wr_issued) ||
                        (top_state == TOP_ST_COMPUTE_WRITE_ISSUE);
  assign wr_cmd_addr  = (top_state == TOP_ST_COMPUTE_WRITE_ISSUE) ?
                        top_row_addr(o_base, compute_q_idx) : o_base;
  assign wr_in_data   = (top_state == TOP_ST_COMPUTE_WRITE_RUN) ?
                        compute_wr_data : rd_data;
  assign wr_in_valid  = (top_state == TOP_ST_COMPUTE_WRITE_RUN) ?
                        1'b1 : rd_valid;
  assign wr_in_last   = (top_state == TOP_ST_COMPUTE_WRITE_RUN) ?
                        (compute_wr_beat_idx == TOP_ROW_BEAT_IDX_W'(TOP_ROW_BEATS - 1)) : rd_last;

  assign row_engine_valid_i   = (top_state == TOP_ST_COMPUTE_ENGINE_ISSUE) &&
                                row_engine_ready;
  assign compute_row_last_key_idx = causal_en ? compute_q_idx : TOP_COMPUTE_LAST_ROW;
  assign compute_key_is_row_last  = (compute_k_idx == compute_row_last_key_idx);
  assign compute_key_is_tile_last = (compute_key_in_tile_idx == TOP_KV_TILE_LAST_OFFSET);
  assign row_engine_row_start     = (compute_k_idx == 8'd0);
  assign row_engine_last          = compute_key_is_row_last;

  fa_dma_rd u_dma_rd (
    .clk           (clk),
    .rst_n         (dma_rst_n),
    .cmd_valid     (rd_cmd_valid),
    .cmd_ready     (rd_cmd_ready),
    .cmd_addr      (rd_cmd_addr),
    .cmd_beats     (9'd16),
    .out_data      (rd_data),
    .out_valid     (rd_valid),
    .out_ready     (rd_out_ready),
    .out_last      (rd_last),
    .done          (rd_done),
    .error         (rd_error),
    .byte_count    (rd_byte_count),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready)
  );

  fa_dma_wr u_dma_wr (
    .clk           (clk),
    .rst_n         (dma_rst_n),
    .cmd_valid     (wr_cmd_valid),
    .cmd_ready     (wr_cmd_ready),
    .cmd_addr      (wr_cmd_addr),
    .cmd_beats     (9'd16),
    .in_data       (wr_in_data),
    .in_valid      (wr_in_valid),
    .in_ready      (wr_in_ready),
    .in_last       (wr_in_last),
    .done          (wr_done),
    .error         (wr_error),
    .byte_count    (wr_byte_count),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      top_state                  <= TOP_ST_IDLE;
      top_dma_smoke_rd_issued    <= 1'b0;
      top_dma_smoke_wr_issued    <= 1'b0;
      top_dma_smoke_rd_done_seen <= 1'b0;
      top_dma_smoke_wr_done_seen <= 1'b0;
      compute_q_idx              <= 8'd0;
      compute_kv_tile_base_idx   <= 8'd0;
      compute_key_in_tile_idx    <= 8'd0;
      compute_k_idx              <= 8'd0;
      compute_rd_beat_idx        <= '0;
      compute_wr_beat_idx        <= '0;
      busy                       <= 1'b0;
      done                       <= 1'b0;
      error                      <= 1'b0;
      cycles                     <= 32'h0;
      for (int lane = 0; lane < TOP_COMPUTE_D; lane++) begin
        compute_q_row[lane] <= '0;
        compute_k_row[lane] <= '0;
        compute_v_row[lane] <= '0;
        compute_o_row[lane] <= '0;
      end
    end else if (soft_reset_pulse) begin
      top_state                  <= TOP_ST_IDLE;
      top_dma_smoke_rd_issued    <= 1'b0;
      top_dma_smoke_wr_issued    <= 1'b0;
      top_dma_smoke_rd_done_seen <= 1'b0;
      top_dma_smoke_wr_done_seen <= 1'b0;
      compute_q_idx              <= 8'd0;
      compute_kv_tile_base_idx   <= 8'd0;
      compute_key_in_tile_idx    <= 8'd0;
      compute_k_idx              <= 8'd0;
      compute_rd_beat_idx        <= '0;
      compute_wr_beat_idx        <= '0;
      busy                       <= 1'b0;
      done                       <= 1'b0;
      error                      <= 1'b0;
      cycles                     <= 32'h0;
      for (int lane = 0; lane < TOP_COMPUTE_D; lane++) begin
        compute_q_row[lane] <= '0;
        compute_k_row[lane] <= '0;
        compute_v_row[lane] <= '0;
        compute_o_row[lane] <= '0;
      end
    end else begin
      if (done_clear) begin
        done <= 1'b0;
      end

      if (busy) begin
        cycles <= cycles + 32'd1;
      end

      if (rd_valid && rd_out_ready) begin
        unique case (top_state)
          TOP_ST_COMPUTE_LOAD_Q_RUN: begin
            for (int lane = 0; lane < TOP_AXI_LANES; lane++) begin
              compute_q_row[(compute_rd_beat_idx * TOP_AXI_LANES) + lane] <=
                  rd_data[(lane * 16) +: 16];
            end
            compute_rd_beat_idx <= compute_rd_beat_idx + 1'b1;
          end
          TOP_ST_COMPUTE_LOAD_K_RUN: begin
            for (int lane = 0; lane < TOP_AXI_LANES; lane++) begin
              compute_k_row[(compute_rd_beat_idx * TOP_AXI_LANES) + lane] <=
                  rd_data[(lane * 16) +: 16];
            end
            compute_rd_beat_idx <= compute_rd_beat_idx + 1'b1;
          end
          TOP_ST_COMPUTE_LOAD_V_RUN: begin
            for (int lane = 0; lane < TOP_AXI_LANES; lane++) begin
              compute_v_row[(compute_rd_beat_idx * TOP_AXI_LANES) + lane] <=
                  rd_data[(lane * 16) +: 16];
            end
            compute_rd_beat_idx <= compute_rd_beat_idx + 1'b1;
          end
          default: begin
          end
        endcase
      end

      unique case (top_state)
        TOP_ST_IDLE: begin
          busy <= 1'b0;
          if (start_pulse) begin
            top_dma_smoke_rd_issued    <= 1'b0;
            top_dma_smoke_wr_issued    <= 1'b0;
            top_dma_smoke_rd_done_seen <= 1'b0;
            top_dma_smoke_wr_done_seen <= 1'b0;
            compute_q_idx              <= 8'd0;
            compute_kv_tile_base_idx   <= 8'd0;
            compute_key_in_tile_idx    <= 8'd0;
            compute_k_idx              <= 8'd0;
            compute_rd_beat_idx        <= '0;
            compute_wr_beat_idx        <= '0;
            busy                       <= 1'b1;
            done                       <= 1'b0;
            error                      <= 1'b0;
            cycles                     <= 32'h0;
            if (compute_smoke_en) begin
              top_state <= TOP_ST_COMPUTE_LOAD_Q_ISSUE;
            end else begin
              top_state <= TOP_ST_DMA_ISSUE;
            end
          end
        end

        TOP_ST_DMA_ISSUE: begin
          if (rd_cmd_valid && rd_cmd_ready) begin
            top_dma_smoke_rd_issued <= 1'b1;
          end
          if (wr_cmd_valid && wr_cmd_ready) begin
            top_dma_smoke_wr_issued <= 1'b1;
          end
          if ((top_dma_smoke_rd_issued || (rd_cmd_valid && rd_cmd_ready)) &&
              (top_dma_smoke_wr_issued || (wr_cmd_valid && wr_cmd_ready))) begin
            top_state <= TOP_ST_DMA_RUN;
          end
        end

        TOP_ST_DMA_RUN: begin
          if (rd_done) begin
            top_dma_smoke_rd_done_seen <= 1'b1;
          end
          if (wr_done) begin
            top_dma_smoke_wr_done_seen <= 1'b1;
          end
          if ((top_dma_smoke_rd_done_seen || rd_done) &&
              (top_dma_smoke_wr_done_seen || wr_done)) begin
            top_state <= TOP_ST_DMA_COMPLETE;
          end
        end

        TOP_ST_DMA_COMPLETE: begin
          busy <= 1'b0;
          if (rd_error || wr_error) begin
            error <= 1'b1;
          end else begin
            done <= 1'b1;
          end
          top_state <= TOP_ST_IDLE;
        end

        TOP_ST_COMPUTE_LOAD_Q_ISSUE: begin
          if (rd_cmd_valid && rd_cmd_ready) begin
            compute_rd_beat_idx <= '0;
            top_state <= TOP_ST_COMPUTE_LOAD_Q_RUN;
          end
        end

        TOP_ST_COMPUTE_LOAD_Q_RUN: begin
          if (rd_done) begin
            if (rd_error) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              compute_kv_tile_base_idx <= 8'd0;
              compute_key_in_tile_idx  <= 8'd0;
              compute_k_idx            <= 8'd0;
              top_state <= TOP_ST_COMPUTE_LOAD_K_ISSUE;
            end
          end
        end

        TOP_ST_COMPUTE_LOAD_K_ISSUE: begin
          if (rd_cmd_valid && rd_cmd_ready) begin
            compute_rd_beat_idx <= '0;
            top_state <= TOP_ST_COMPUTE_LOAD_K_RUN;
          end
        end

        TOP_ST_COMPUTE_LOAD_K_RUN: begin
          if (rd_done) begin
            if (rd_error) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              top_state <= TOP_ST_COMPUTE_LOAD_V_ISSUE;
            end
          end
        end

        TOP_ST_COMPUTE_LOAD_V_ISSUE: begin
          if (rd_cmd_valid && rd_cmd_ready) begin
            compute_rd_beat_idx <= '0;
            top_state <= TOP_ST_COMPUTE_LOAD_V_RUN;
          end
        end

        TOP_ST_COMPUTE_LOAD_V_RUN: begin
          if (rd_done) begin
            if (rd_error) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              top_state <= TOP_ST_COMPUTE_ENGINE_ISSUE;
            end
          end
        end

        TOP_ST_COMPUTE_ENGINE_ISSUE: begin
          if (row_engine_ready) begin
            top_state <= TOP_ST_COMPUTE_ENGINE_WAIT;
          end
        end

        TOP_ST_COMPUTE_ENGINE_WAIT: begin
          if (!compute_key_is_row_last) begin
            if (compute_key_is_tile_last) begin
              compute_kv_tile_base_idx <= compute_kv_tile_base_idx + 8'(KV_TILE_ROWS);
              compute_key_in_tile_idx  <= 8'd0;
              compute_k_idx            <= compute_kv_tile_base_idx + 8'(KV_TILE_ROWS);
            end else begin
              compute_key_in_tile_idx <= compute_key_in_tile_idx + 8'd1;
              compute_k_idx           <= compute_k_idx + 8'd1;
            end
            top_state <= TOP_ST_COMPUTE_LOAD_K_ISSUE;
          end else if (row_engine_valid_o) begin
            if (row_engine_div_zero) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              for (int lane = 0; lane < TOP_COMPUTE_D; lane++) begin
                compute_o_row[lane] <= row_engine_o[lane];
              end
              top_state <= TOP_ST_COMPUTE_WRITE_ISSUE;
            end
          end
        end

        TOP_ST_COMPUTE_WRITE_ISSUE: begin
          if (wr_cmd_valid && wr_cmd_ready) begin
            compute_wr_beat_idx <= '0;
            top_state <= TOP_ST_COMPUTE_WRITE_RUN;
          end
        end

        TOP_ST_COMPUTE_WRITE_RUN: begin
          if (wr_in_valid && wr_in_ready) begin
            compute_wr_beat_idx <= compute_wr_beat_idx + 1'b1;
          end
          if (wr_done) begin
            if (wr_error) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else if (compute_q_idx == TOP_COMPUTE_LAST_ROW) begin
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              compute_q_idx            <= compute_q_idx + 8'd1;
              compute_kv_tile_base_idx <= 8'd0;
              compute_key_in_tile_idx  <= 8'd0;
              compute_k_idx            <= 8'd0;
              top_state <= TOP_ST_COMPUTE_LOAD_Q_ISSUE;
            end
          end
        end

        TOP_ST_COMPUTE_COMPLETE: begin
          busy <= 1'b0;
          if (!error) begin
            done <= 1'b1;
          end
          top_state <= TOP_ST_IDLE;
        end

        default: begin
          busy      <= 1'b0;
          error     <= 1'b1;
          top_state <= TOP_ST_IDLE;
        end
      endcase
    end
  end

  logic unused_top;
  assign unused_top = rd_byte_count[0] ^ wr_byte_count[0] ^
                      stride_bytes[0] ^ row_engine_busy;
endmodule
