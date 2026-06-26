`timescale 1ns/1ps

import fa_pkg::*;

module fa_accel_top (
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
  logic        start_pulse;
  logic        soft_reset_pulse;
  logic        irq_en;
  logic        causal_en;
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
  logic [63:0] rd_data;
  logic        rd_valid;
  logic        rd_ready;
  logic        rd_last;
  logic        rd_done;
  logic        rd_error;
  logic [31:0] rd_byte_count;

  logic        wr_cmd_valid;
  logic        wr_cmd_ready;
  logic        wr_done;
  logic        wr_error;
  logic [31:0] wr_byte_count;

  typedef enum logic [1:0] {
    TOP_DMA_SMOKE_IDLE,
    TOP_DMA_SMOKE_ISSUE,
    TOP_DMA_SMOKE_RUN,
    TOP_DMA_SMOKE_COMPLETE
  } top_dma_smoke_state_e;

  top_dma_smoke_state_e top_dma_smoke_state;
  logic                 top_dma_smoke_rd_issued;
  logic                 top_dma_smoke_wr_issued;
  logic                 top_dma_smoke_rd_done_seen;
  logic                 top_dma_smoke_wr_done_seen;

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

  assign dma_rst_n    = rst_n & !soft_reset_pulse;
  assign irq          = irq_en & done;
  assign rd_cmd_valid = (top_dma_smoke_state == TOP_DMA_SMOKE_ISSUE) &&
                        !top_dma_smoke_rd_issued;
  assign wr_cmd_valid = (top_dma_smoke_state == TOP_DMA_SMOKE_ISSUE) &&
                        !top_dma_smoke_wr_issued;

  fa_dma_rd u_dma_rd (
    .clk           (clk),
    .rst_n         (dma_rst_n),
    .cmd_valid     (rd_cmd_valid),
    .cmd_ready     (rd_cmd_ready),
    .cmd_addr      (q_base),
    .cmd_beats     (9'd16),
    .out_data      (rd_data),
    .out_valid     (rd_valid),
    .out_ready     (rd_ready),
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
    .cmd_addr      (o_base),
    .cmd_beats     (9'd16),
    .in_data       (rd_data),
    .in_valid      (rd_valid),
    .in_ready      (rd_ready),
    .in_last       (rd_last),
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
      top_dma_smoke_state        <= TOP_DMA_SMOKE_IDLE;
      top_dma_smoke_rd_issued    <= 1'b0;
      top_dma_smoke_wr_issued    <= 1'b0;
      top_dma_smoke_rd_done_seen <= 1'b0;
      top_dma_smoke_wr_done_seen <= 1'b0;
      busy                       <= 1'b0;
      done                       <= 1'b0;
      error                      <= 1'b0;
      cycles                     <= 32'h0;
    end else if (soft_reset_pulse) begin
      top_dma_smoke_state        <= TOP_DMA_SMOKE_IDLE;
      top_dma_smoke_rd_issued    <= 1'b0;
      top_dma_smoke_wr_issued    <= 1'b0;
      top_dma_smoke_rd_done_seen <= 1'b0;
      top_dma_smoke_wr_done_seen <= 1'b0;
      busy                       <= 1'b0;
      done                       <= 1'b0;
      error                      <= 1'b0;
      cycles                     <= 32'h0;
    end else begin
      if (done_clear) begin
        done <= 1'b0;
      end

      if (busy) begin
        cycles <= cycles + 32'd1;
      end

      unique case (top_dma_smoke_state)
        TOP_DMA_SMOKE_IDLE: begin
          busy <= 1'b0;
          if (start_pulse) begin
            top_dma_smoke_state        <= TOP_DMA_SMOKE_ISSUE;
            top_dma_smoke_rd_issued    <= 1'b0;
            top_dma_smoke_wr_issued    <= 1'b0;
            top_dma_smoke_rd_done_seen <= 1'b0;
            top_dma_smoke_wr_done_seen <= 1'b0;
            busy                       <= 1'b1;
            done                       <= 1'b0;
            error                      <= 1'b0;
            cycles                     <= 32'h0;
          end
        end

        TOP_DMA_SMOKE_ISSUE: begin
          if (rd_cmd_valid && rd_cmd_ready) begin
            top_dma_smoke_rd_issued <= 1'b1;
          end
          if (wr_cmd_valid && wr_cmd_ready) begin
            top_dma_smoke_wr_issued <= 1'b1;
          end
          if ((top_dma_smoke_rd_issued || (rd_cmd_valid && rd_cmd_ready)) &&
              (top_dma_smoke_wr_issued || (wr_cmd_valid && wr_cmd_ready))) begin
            top_dma_smoke_state <= TOP_DMA_SMOKE_RUN;
          end
        end

        TOP_DMA_SMOKE_RUN: begin
          if (rd_done) begin
            top_dma_smoke_rd_done_seen <= 1'b1;
          end
          if (wr_done) begin
            top_dma_smoke_wr_done_seen <= 1'b1;
          end
          if ((top_dma_smoke_rd_done_seen || rd_done) &&
              (top_dma_smoke_wr_done_seen || wr_done)) begin
            top_dma_smoke_state <= TOP_DMA_SMOKE_COMPLETE;
          end
        end

        TOP_DMA_SMOKE_COMPLETE: begin
          busy <= 1'b0;
          if (rd_error || wr_error) begin
            error <= 1'b1;
          end else begin
            done <= 1'b1;
          end
          top_dma_smoke_state <= TOP_DMA_SMOKE_IDLE;
        end

        default: begin
          busy                <= 1'b0;
          error               <= 1'b1;
          top_dma_smoke_state <= TOP_DMA_SMOKE_IDLE;
        end
      endcase
    end
  end

  logic unused_top_dma_smoke;
  assign unused_top_dma_smoke = rd_byte_count[0] ^ wr_byte_count[0] ^
                                stride_bytes[0];
endmodule
