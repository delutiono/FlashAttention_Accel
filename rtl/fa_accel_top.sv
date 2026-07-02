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
  localparam int unsigned TOP_Q_GROUP_ROWS = FA_Q_GROUP_ROWS;
  localparam int unsigned TOP_KV_TILE_ROWS = FA_KV_TILE_ROWS;
  localparam int unsigned TOP_GROUP_BEATS = FA_GROUP_BEATS;
  localparam int unsigned TOP_GROUPS = (COMPUTE_ROWS + TOP_Q_GROUP_ROWS - 1) / TOP_Q_GROUP_ROWS;
  localparam int unsigned TOP_KV_TILE_IDX_W = (TOP_KV_TILE_ROWS <= 1) ? 1 : $clog2(TOP_KV_TILE_ROWS);
  localparam int unsigned TOP_BUFFER_READ_WAIT_CYCLES = 2;
  localparam int unsigned TOP_BUFFER_READ_WAIT_W = $clog2(TOP_BUFFER_READ_WAIT_CYCLES + 1);
  localparam logic [7:0] TOP_COMPUTE_LAST_ROW = COMPUTE_ROWS - 1;
  localparam logic [7:0] TOP_KV_TILE_LAST_OFFSET = TOP_KV_TILE_ROWS - 1;

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
  logic [8:0]  rd_cmd_beats;
  logic [FA_AXI_DATA_W-1:0] rd_data;
  logic        rd_valid;
  logic        rd_out_ready;
  logic        rd_last;
  logic        rd_done;
  logic        rd_error;
  logic [31:0] rd_byte_count;

  logic        wr_cmd_valid;
  logic        wr_cmd_ready;
  logic [63:0] wr_cmd_addr;
  logic [8:0]  wr_cmd_beats;
  logic [FA_AXI_DATA_W-1:0] wr_in_data;
  logic        wr_in_valid;
  logic        wr_in_ready;
  logic        wr_in_last;
  logic        wr_done;
  logic        wr_error;
  logic [31:0] wr_byte_count;

  logic signed [FA_ELEM_W-1:0] compute_o_row [TOP_COMPUTE_D];

  logic                         q_buffer_clear;
  logic                         q_buffer_beat_valid;
  logic                         q_buffer_beat_ready;
  logic                         q_buffer_load_done;
  logic signed [FA_ELEM_W-1:0]  q_buffer_row [TOP_COMPUTE_D];

  logic                         kv_buffer_clear;
  logic                         kv_buffer_k_beat_valid;
  logic                         kv_buffer_k_beat_ready;
  logic                         kv_buffer_k_load_done;
  logic                         kv_buffer_v_beat_valid;
  logic                         kv_buffer_v_beat_ready;
  logic                         kv_buffer_v_load_done;
  logic [TOP_KV_TILE_IDX_W-1:0] kv_buffer_row_index;
  logic signed [FA_ELEM_W-1:0]  kv_buffer_k_row [TOP_COMPUTE_D];
  logic signed [FA_ELEM_W-1:0]  kv_buffer_v_row [TOP_COMPUTE_D];

  logic        row_engine_valid_i;
  logic        row_engine_row_start;
  logic        row_engine_last;
  logic        row_engine_ready;
  logic        row_engine_busy;
  logic        row_engine_valid_o;
  logic        row_engine_div_zero;
  logic signed [FA_ELEM_W-1:0] row_engine_o [TOP_COMPUTE_D];

  logic                         group_engine_init_valid;
  logic                         group_engine_init_ready;
  logic [2:0]                   group_engine_init_context;
  logic                         group_engine_score_valid;
  logic                         group_engine_score_ready;
  logic                         group_engine_context_done_valid;
  logic [2:0]                   group_engine_context_done;
  logic                         group_engine_final_valid;
  logic [2:0]                   group_engine_final_context;
  logic                         group_engine_div_zero;
  logic signed [FA_ELEM_W-1:0]  group_engine_final_row [TOP_COMPUTE_D];

  logic                         o_group_store_clear;
  logic                         o_group_store_group_ready;
  logic                         o_group_store_start;
  logic                         o_group_store_beat_valid;
  logic                         o_group_store_beat_ready;
  logic [FA_AXI_DATA_W-1:0]     o_group_store_beat_data;
  logic                         o_group_store_beat_last;
  logic                         o_group_store_done;
  logic [TOP_Q_GROUP_ROWS-1:0]  compute_group_active_mask;

  logic [4:0] scheduler_q_group;
  logic [7:0] scheduler_kv_tile;
  logic [2:0] scheduler_q_context;
  logic [2:0] scheduler_kv_row;
  logic       scheduler_score_last;
  logic       scheduler_tile_done;
  logic       scheduler_group_done;

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
    TOP_ST_COMPUTE_INIT_CONTEXT,
    TOP_ST_COMPUTE_BUFFER_READ_WAIT,
    TOP_ST_COMPUTE_ENGINE_ISSUE,
    TOP_ST_COMPUTE_ENGINE_WAIT,
    TOP_ST_COMPUTE_RUN_TILE,
    TOP_ST_COMPUTE_WAIT_GROUP_FINAL,
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
  logic [4:0] compute_q_group_idx;
  logic [4:0] compute_kv_tile_idx;
  logic [2:0] compute_q_context_idx;
  logic [2:0] compute_kv_row_idx;
  logic [2:0] compute_init_context_idx;
  logic [7:0] compute_kv_tile_base_idx;
  logic [7:0] compute_key_in_tile_idx;
  logic [7:0] compute_k_idx;
  logic [TOP_BUFFER_READ_WAIT_W-1:0] compute_buffer_wait_q;
  logic [TOP_ROW_BEAT_IDX_W-1:0] compute_wr_beat_idx;
  logic [63:0] compute_rd_addr;
  logic [FA_AXI_DATA_W-1:0] compute_wr_data;
  logic [7:0]  compute_row_last_key_idx;
  logic [7:0]  compute_tile_nominal_last_key_idx;
  logic [7:0]  compute_tile_last_key_idx;
  logic [7:0]  compute_tile_last_offset;
  logic        compute_key_is_row_last;
  logic        compute_key_is_tile_last;
  logic        compute_tile_is_full;
  logic [7:0]  compute_group_base_row;
  logic [7:0]  compute_group_last_row;
  logic [7:0]  compute_group_last_tile_idx;
  logic [7:0]  compute_global_q_idx;
  logic [7:0]  compute_global_k_idx;
  logic        compute_pair_legal;
  logic        compute_pair_last_in_tile;
  logic        compute_tile_is_group_last;
  logic [63:0] compute_group_rd_addr;
  logic [63:0] compute_tile_rd_addr;
  logic [63:0] compute_group_wr_addr;

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

  function automatic logic [63:0] top_group_addr(
    input logic [63:0] base,
    input logic [4:0]  group
  );
    begin
      top_group_addr = base + ({59'h0, group} * 64'd1024);
    end
  endfunction

  function automatic logic [63:0] top_tile_addr(
    input logic [63:0] base,
    input logic [4:0]  tile
  );
    begin
      top_tile_addr = base + ({59'h0, tile} * 64'd1024);
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
    .kv_tile_o        (scheduler_kv_tile),
    .k_index_o        (),
    .score_valid_o    (),
    .q_group_o        (scheduler_q_group),
    .q_context_o      (scheduler_q_context),
    .kv_row_o         (scheduler_kv_row),
    .score_last_o     (scheduler_score_last),
    .tile_done_o      (scheduler_tile_done),
    .group_done_o     (scheduler_group_done)
  );

  fa_q_buffer #(
    .D(TOP_COMPUTE_D),
    .ELEM_W(FA_ELEM_W),
    .BEAT_W(FA_AXI_DATA_W),
    .GROUP_ROWS(TOP_Q_GROUP_ROWS)
  ) u_q_buffer (
    .clk,
    .rst_n          (dma_rst_n),
    .clear_i        (q_buffer_clear),
    .beat_valid_i   (q_buffer_beat_valid),
    .beat_ready_o   (q_buffer_beat_ready),
    .beat_data_i    (rd_data),
    .row_index_i    (compute_q_context_idx),
    .load_done_o    (q_buffer_load_done),
    .q_o            (q_buffer_row)
  );

  fa_kv_buffer #(
    .TILE_ROWS(TOP_KV_TILE_ROWS),
    .D(TOP_COMPUTE_D),
    .ELEM_W(FA_ELEM_W),
    .BEAT_W(FA_AXI_DATA_W),
    .ROW_INDEX_W(TOP_KV_TILE_IDX_W)
  ) u_kv_buffer (
    .clk,
    .rst_n          (dma_rst_n),
    .clear_i        (kv_buffer_clear),
    .k_valid_i      (kv_buffer_k_beat_valid),
    .k_ready_o      (kv_buffer_k_beat_ready),
    .k_data_i       (rd_data),
    .k_load_done_o  (kv_buffer_k_load_done),
    .v_valid_i      (kv_buffer_v_beat_valid),
    .v_ready_o      (kv_buffer_v_beat_ready),
    .v_data_i       (rd_data),
    .v_load_done_o  (kv_buffer_v_load_done),
    .row_index_i    (kv_buffer_row_index),
    .k_o            (kv_buffer_k_row),
    .v_o            (kv_buffer_v_row)
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
    .q_i               (q_buffer_row),
    .k_i               (kv_buffer_k_row),
    .v_i               (kv_buffer_v_row),
    .ready_o           (row_engine_ready),
    .busy_o            (row_engine_busy),
    .valid_o           (row_engine_valid_o),
    .div_zero_o        (row_engine_div_zero),
    .o_q88_o           (row_engine_o)
  );

  fa_group_engine #(
    .D(TOP_COMPUTE_D),
    .GROUP_ROWS(TOP_Q_GROUP_ROWS),
    .ELEM_W(FA_ELEM_W)
  ) u_group_engine (
    .clk,
    .rst_n                 (dma_rst_n),
    .init_valid_i          (group_engine_init_valid),
    .init_ready_o          (group_engine_init_ready),
    .init_context_i        (group_engine_init_context),
    .score_valid_i         (group_engine_score_valid),
    .score_ready_o         (group_engine_score_ready),
    .score_context_i       (compute_q_context_idx),
    .q_index_i             (compute_global_q_idx),
    .k_index_i             (compute_global_k_idx),
    .score_last_i          (compute_global_k_idx == compute_global_q_idx),
    .q_i                   (q_buffer_row),
    .k_i                   (kv_buffer_k_row),
    .v_i                   (kv_buffer_v_row),
    .context_done_valid_o  (group_engine_context_done_valid),
    .context_done_o        (group_engine_context_done),
    .final_valid_o         (group_engine_final_valid),
    .final_context_o       (group_engine_final_context),
    .div_zero_o            (group_engine_div_zero),
    .final_o               (group_engine_final_row)
  );

  fa_o_group_store u_o_group_store (
    .clk,
    .rst_n           (dma_rst_n),
    .clear_i         (o_group_store_clear),
    .final_valid_i   (group_engine_final_valid),
    .final_context_i (group_engine_final_context),
    .final_i         (group_engine_final_row),
    .active_rows_i   (compute_group_active_mask),
    .group_ready_o   (o_group_store_group_ready),
    .start_i         (o_group_store_start),
    .beat_valid_o    (o_group_store_beat_valid),
    .beat_ready_i    (o_group_store_beat_ready),
    .beat_data_o     (o_group_store_beat_data),
    .beat_last_o     (o_group_store_beat_last),
    .done_o          (o_group_store_done)
  );

  assign dma_rst_n = rst_n & !soft_reset_pulse;
  assign irq       = irq_en & done;

  assign compute_group_base_row = {compute_q_group_idx, 3'b000};
  assign compute_group_last_row =
      (({compute_q_group_idx, 3'b000} + 8'd7) > TOP_COMPUTE_LAST_ROW) ?
      TOP_COMPUTE_LAST_ROW : ({compute_q_group_idx, 3'b000} + 8'd7);
  assign compute_group_last_tile_idx = compute_group_last_row >> 3;
  assign compute_global_q_idx = {compute_q_group_idx, compute_q_context_idx};
  assign compute_global_k_idx = {compute_kv_tile_idx, compute_kv_row_idx};
  assign compute_pair_legal = (compute_global_q_idx <= TOP_COMPUTE_LAST_ROW) &&
                              (compute_global_k_idx <= TOP_COMPUTE_LAST_ROW) &&
                              (!causal_en || (compute_global_k_idx <= compute_global_q_idx));
  always_comb begin
    compute_group_active_mask = '0;
    for (int row = 0; row < TOP_Q_GROUP_ROWS; row++) begin
      if ((compute_group_base_row + 8'(row)) <= TOP_COMPUTE_LAST_ROW) begin
        compute_group_active_mask[row] = 1'b1;
      end
    end
  end

  assign compute_pair_last_in_tile = (compute_q_context_idx == 3'd7) &&
                                     (compute_kv_row_idx == 3'd7);
  assign compute_tile_is_group_last = (compute_kv_tile_idx == compute_group_last_tile_idx[4:0]);
  assign compute_group_rd_addr = top_group_addr(q_base, compute_q_group_idx);
  assign compute_tile_rd_addr =
      ((top_state == TOP_ST_COMPUTE_LOAD_K_ISSUE) ||
       (top_state == TOP_ST_COMPUTE_LOAD_K_RUN)) ?
      top_tile_addr(k_base, compute_kv_tile_idx) :
      top_tile_addr(v_base, compute_kv_tile_idx);
  assign compute_group_wr_addr = top_group_addr(o_base, compute_q_group_idx);

  always_comb begin
    compute_rd_addr = 64'h0;
    unique case (top_state)
      TOP_ST_COMPUTE_LOAD_Q_ISSUE,
      TOP_ST_COMPUTE_LOAD_Q_RUN: compute_rd_addr = compute_group_rd_addr;
      TOP_ST_COMPUTE_LOAD_K_ISSUE,
      TOP_ST_COMPUTE_LOAD_K_RUN: compute_rd_addr = compute_tile_rd_addr;
      TOP_ST_COMPUTE_LOAD_V_ISSUE,
      TOP_ST_COMPUTE_LOAD_V_RUN: compute_rd_addr = compute_tile_rd_addr;
      default: compute_rd_addr = q_base;
    endcase
  end

  always_comb begin
    compute_wr_data = '0;
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
  assign rd_cmd_beats = ((top_state == TOP_ST_COMPUTE_LOAD_Q_ISSUE) ||
                         (top_state == TOP_ST_COMPUTE_LOAD_K_ISSUE) ||
                         (top_state == TOP_ST_COMPUTE_LOAD_V_ISSUE)) ?
                        9'(TOP_GROUP_BEATS) : 9'(TOP_ROW_BEATS);
  assign rd_out_ready = (top_state == TOP_ST_COMPUTE_LOAD_Q_RUN) ? q_buffer_beat_ready :
                        (top_state == TOP_ST_COMPUTE_LOAD_K_RUN) ? kv_buffer_k_beat_ready :
                        (top_state == TOP_ST_COMPUTE_LOAD_V_RUN) ? kv_buffer_v_beat_ready :
                        wr_in_ready;

  assign wr_cmd_valid = (top_state == TOP_ST_DMA_ISSUE &&
                        !top_dma_smoke_wr_issued) ||
                        (top_state == TOP_ST_COMPUTE_WRITE_ISSUE);
  assign wr_cmd_addr  = (top_state == TOP_ST_COMPUTE_WRITE_ISSUE) ?
                        compute_group_wr_addr : o_base;
  assign wr_cmd_beats = (top_state == TOP_ST_COMPUTE_WRITE_ISSUE) ?
                        9'(TOP_GROUP_BEATS) : 9'(TOP_ROW_BEATS);
  assign wr_in_data   = (top_state == TOP_ST_COMPUTE_WRITE_RUN) ?
                        o_group_store_beat_data : rd_data;
  assign wr_in_valid  = (top_state == TOP_ST_COMPUTE_WRITE_RUN) ?
                        o_group_store_beat_valid : rd_valid;
  assign wr_in_last   = (top_state == TOP_ST_COMPUTE_WRITE_RUN) ?
                        o_group_store_beat_last : rd_last;
  assign o_group_store_beat_ready = (top_state == TOP_ST_COMPUTE_WRITE_RUN) && wr_in_ready;

  assign row_engine_valid_i   = (top_state == TOP_ST_COMPUTE_ENGINE_ISSUE) &&
                                row_engine_ready;
  assign compute_row_last_key_idx = causal_en ? compute_q_idx : TOP_COMPUTE_LAST_ROW;
  assign compute_tile_nominal_last_key_idx =
      compute_kv_tile_base_idx + 8'(TOP_KV_TILE_ROWS - 1);
  assign compute_tile_last_key_idx =
      (compute_tile_nominal_last_key_idx > compute_row_last_key_idx) ?
      compute_row_last_key_idx : compute_tile_nominal_last_key_idx;
  assign compute_tile_last_offset =
      (compute_tile_last_key_idx > compute_kv_tile_base_idx) ?
      (compute_tile_last_key_idx - compute_kv_tile_base_idx) : 8'd0;
  assign compute_key_is_row_last  = (compute_k_idx == compute_row_last_key_idx);
  assign compute_key_is_tile_last = (compute_key_in_tile_idx == compute_tile_last_offset);
  assign compute_tile_is_full     = (compute_tile_last_offset == TOP_KV_TILE_LAST_OFFSET);
  assign row_engine_row_start     = (compute_k_idx == 8'd0);
  assign row_engine_last          = compute_key_is_row_last;
  assign q_buffer_clear           = (top_state == TOP_ST_COMPUTE_LOAD_Q_ISSUE);
  assign q_buffer_beat_valid      = (top_state == TOP_ST_COMPUTE_LOAD_Q_RUN) && rd_valid;
  assign kv_buffer_clear          = (top_state == TOP_ST_COMPUTE_LOAD_K_ISSUE);
  assign kv_buffer_k_beat_valid   = (top_state == TOP_ST_COMPUTE_LOAD_K_RUN) && rd_valid;
  assign kv_buffer_v_beat_valid   = (top_state == TOP_ST_COMPUTE_LOAD_V_RUN) && rd_valid;
  assign kv_buffer_row_index      = compute_kv_row_idx[TOP_KV_TILE_IDX_W-1:0];
  assign group_engine_init_valid  = (top_state == TOP_ST_COMPUTE_INIT_CONTEXT);
  assign group_engine_init_context = compute_init_context_idx;
  assign group_engine_score_valid = (top_state == TOP_ST_COMPUTE_ENGINE_ISSUE) &&
                                    compute_pair_legal && group_engine_score_ready;
  assign o_group_store_clear      = (top_state == TOP_ST_COMPUTE_LOAD_Q_ISSUE);
  assign o_group_store_start      = (top_state == TOP_ST_COMPUTE_WRITE_ISSUE) &&
                                    wr_cmd_valid && wr_cmd_ready;

  fa_dma_rd #(
    .DATA_W        (FA_AXI_DATA_W)
  ) u_dma_rd (
    .clk           (clk),
    .rst_n         (dma_rst_n),
    .cmd_valid     (rd_cmd_valid),
    .cmd_ready     (rd_cmd_ready),
    .cmd_addr      (rd_cmd_addr),
    .cmd_beats     (rd_cmd_beats),
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

  fa_dma_wr #(
    .DATA_W        (FA_AXI_DATA_W)
  ) u_dma_wr (
    .clk           (clk),
    .rst_n         (dma_rst_n),
    .cmd_valid     (wr_cmd_valid),
    .cmd_ready     (wr_cmd_ready),
    .cmd_addr      (wr_cmd_addr),
    .cmd_beats     (wr_cmd_beats),
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
      compute_q_group_idx        <= '0;
      compute_kv_tile_idx        <= '0;
      compute_q_context_idx      <= '0;
      compute_kv_row_idx         <= '0;
      compute_init_context_idx   <= '0;
      compute_kv_tile_base_idx   <= 8'd0;
      compute_key_in_tile_idx    <= 8'd0;
      compute_k_idx              <= 8'd0;
      compute_buffer_wait_q      <= '0;
      compute_wr_beat_idx        <= '0;
      busy                       <= 1'b0;
      done                       <= 1'b0;
      error                      <= 1'b0;
      cycles                     <= 32'h0;
      for (int lane = 0; lane < TOP_COMPUTE_D; lane++) begin
        compute_o_row[lane] <= '0;
      end
    end else if (soft_reset_pulse) begin
      top_state                  <= TOP_ST_IDLE;
      top_dma_smoke_rd_issued    <= 1'b0;
      top_dma_smoke_wr_issued    <= 1'b0;
      top_dma_smoke_rd_done_seen <= 1'b0;
      top_dma_smoke_wr_done_seen <= 1'b0;
      compute_q_idx              <= 8'd0;
      compute_q_group_idx        <= '0;
      compute_kv_tile_idx        <= '0;
      compute_q_context_idx      <= '0;
      compute_kv_row_idx         <= '0;
      compute_init_context_idx   <= '0;
      compute_kv_tile_base_idx   <= 8'd0;
      compute_key_in_tile_idx    <= 8'd0;
      compute_k_idx              <= 8'd0;
      compute_buffer_wait_q      <= '0;
      compute_wr_beat_idx        <= '0;
      busy                       <= 1'b0;
      done                       <= 1'b0;
      error                      <= 1'b0;
      cycles                     <= 32'h0;
      for (int lane = 0; lane < TOP_COMPUTE_D; lane++) begin
        compute_o_row[lane] <= '0;
      end
    end else begin
      if (done_clear) begin
        done <= 1'b0;
      end

      if (busy) begin
        cycles <= cycles + 32'd1;
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
            compute_q_group_idx        <= '0;
            compute_kv_tile_idx        <= '0;
            compute_q_context_idx      <= '0;
            compute_kv_row_idx         <= '0;
            compute_init_context_idx   <= '0;
            compute_kv_tile_base_idx   <= 8'd0;
            compute_key_in_tile_idx    <= 8'd0;
            compute_k_idx              <= 8'd0;
            compute_buffer_wait_q      <= '0;
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
            top_state <= TOP_ST_COMPUTE_LOAD_Q_RUN;
          end
        end

        TOP_ST_COMPUTE_LOAD_Q_RUN: begin
          if (rd_done) begin
            if (rd_error || !q_buffer_load_done) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              compute_init_context_idx <= '0;
              top_state <= TOP_ST_COMPUTE_INIT_CONTEXT;
            end
          end
        end

        TOP_ST_COMPUTE_INIT_CONTEXT: begin
          if (group_engine_init_ready) begin
            if (compute_init_context_idx == 3'd7) begin
              compute_kv_tile_idx      <= '0;
              compute_kv_tile_base_idx <= 8'd0;
              compute_kv_row_idx       <= '0;
              compute_q_context_idx    <= '0;
              compute_key_in_tile_idx  <= 8'd0;
              compute_k_idx            <= 8'd0;
              top_state <= TOP_ST_COMPUTE_LOAD_K_ISSUE;
            end else begin
              compute_init_context_idx <= compute_init_context_idx + 1'b1;
            end
          end
        end

        TOP_ST_COMPUTE_LOAD_K_ISSUE: begin
          if (rd_cmd_valid && rd_cmd_ready) begin
            top_state <= TOP_ST_COMPUTE_LOAD_K_RUN;
          end
        end

        TOP_ST_COMPUTE_LOAD_K_RUN: begin
          if (rd_done) begin
            if (rd_error || !kv_buffer_k_load_done) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              compute_kv_row_idx      <= '0;
              compute_q_context_idx   <= '0;
              top_state               <= TOP_ST_COMPUTE_LOAD_V_ISSUE;
            end
          end
        end

        TOP_ST_COMPUTE_LOAD_V_ISSUE: begin
          if (rd_cmd_valid && rd_cmd_ready) begin
            top_state <= TOP_ST_COMPUTE_LOAD_V_RUN;
          end
        end

        TOP_ST_COMPUTE_LOAD_V_RUN: begin
          if (rd_done) begin
            if (rd_error || !kv_buffer_v_load_done) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              compute_kv_row_idx      <= '0;
              compute_q_context_idx   <= '0;
              compute_buffer_wait_q   <= '0;
              top_state               <= TOP_ST_COMPUTE_BUFFER_READ_WAIT;
            end
          end
        end

        TOP_ST_COMPUTE_BUFFER_READ_WAIT: begin
          // SRAM 读口同步返回数据；切换 row_index 后等待 bank 输出稳定再发给 row_engine。
          if (compute_buffer_wait_q == TOP_BUFFER_READ_WAIT_W'(TOP_BUFFER_READ_WAIT_CYCLES - 1)) begin
            compute_buffer_wait_q <= '0;
            top_state <= TOP_ST_COMPUTE_ENGINE_ISSUE;
          end else begin
            compute_buffer_wait_q <= compute_buffer_wait_q + 1'b1;
          end
        end

        TOP_ST_COMPUTE_ENGINE_ISSUE: begin
          if (!compute_pair_legal) begin
            if (compute_pair_last_in_tile) begin
              if (compute_tile_is_group_last) begin
                top_state <= TOP_ST_COMPUTE_WAIT_GROUP_FINAL;
              end else begin
                compute_kv_tile_idx      <= compute_kv_tile_idx + 1'b1;
                compute_kv_tile_base_idx <= compute_kv_tile_base_idx + 8'(TOP_KV_TILE_ROWS);
                compute_kv_row_idx       <= '0;
                compute_q_context_idx    <= '0;
                top_state                <= TOP_ST_COMPUTE_LOAD_K_ISSUE;
              end
            end else if (compute_q_context_idx == 3'd7) begin
              compute_q_context_idx <= '0;
              compute_kv_row_idx    <= compute_kv_row_idx + 1'b1;
              compute_buffer_wait_q <= '0;
              top_state             <= TOP_ST_COMPUTE_BUFFER_READ_WAIT;
            end else begin
              compute_q_context_idx <= compute_q_context_idx + 1'b1;
              compute_buffer_wait_q <= '0;
              top_state             <= TOP_ST_COMPUTE_BUFFER_READ_WAIT;
            end
          end else if (group_engine_score_ready) begin
            if (compute_pair_last_in_tile) begin
              if (compute_tile_is_group_last) begin
                top_state <= TOP_ST_COMPUTE_WAIT_GROUP_FINAL;
              end else begin
                compute_kv_tile_idx      <= compute_kv_tile_idx + 1'b1;
                compute_kv_tile_base_idx <= compute_kv_tile_base_idx + 8'(TOP_KV_TILE_ROWS);
                compute_kv_row_idx       <= '0;
                compute_q_context_idx    <= '0;
                top_state                <= TOP_ST_COMPUTE_LOAD_K_ISSUE;
              end
            end else if (compute_q_context_idx == 3'd7) begin
              compute_q_context_idx <= '0;
              compute_kv_row_idx    <= compute_kv_row_idx + 1'b1;
              compute_buffer_wait_q <= '0;
              top_state             <= TOP_ST_COMPUTE_BUFFER_READ_WAIT;
            end else begin
              compute_q_context_idx <= compute_q_context_idx + 1'b1;
              compute_buffer_wait_q <= '0;
              top_state             <= TOP_ST_COMPUTE_BUFFER_READ_WAIT;
            end
          end
        end

        TOP_ST_COMPUTE_ENGINE_WAIT: begin
          if (group_engine_context_done_valid &&
              (group_engine_context_done == compute_q_context_idx)) begin
            if (compute_pair_last_in_tile) begin
              if (compute_tile_is_group_last) begin
                top_state <= TOP_ST_COMPUTE_WAIT_GROUP_FINAL;
              end else begin
                compute_kv_tile_idx      <= compute_kv_tile_idx + 1'b1;
                compute_kv_tile_base_idx <= compute_kv_tile_base_idx + 8'(TOP_KV_TILE_ROWS);
                compute_kv_row_idx       <= '0;
                compute_q_context_idx    <= '0;
                top_state                <= TOP_ST_COMPUTE_LOAD_K_ISSUE;
              end
            end else if (compute_q_context_idx == 3'd7) begin
              compute_q_context_idx <= '0;
              compute_kv_row_idx    <= compute_kv_row_idx + 1'b1;
              compute_buffer_wait_q <= '0;
              top_state             <= TOP_ST_COMPUTE_BUFFER_READ_WAIT;
            end else begin
              compute_q_context_idx <= compute_q_context_idx + 1'b1;
              compute_buffer_wait_q <= '0;
              top_state             <= TOP_ST_COMPUTE_BUFFER_READ_WAIT;
            end
          end
        end

        TOP_ST_COMPUTE_WAIT_GROUP_FINAL: begin
          if (group_engine_div_zero) begin
            error <= 1'b1;
            top_state <= TOP_ST_COMPUTE_COMPLETE;
          end else if (o_group_store_group_ready) begin
            top_state <= TOP_ST_COMPUTE_WRITE_ISSUE;
          end
        end

        TOP_ST_COMPUTE_WRITE_ISSUE: begin
          if (wr_cmd_valid && wr_cmd_ready) begin
            compute_wr_beat_idx <= '0;
            top_state <= TOP_ST_COMPUTE_WRITE_RUN;
          end
        end

        TOP_ST_COMPUTE_WRITE_RUN: begin
          if (wr_done) begin
            if (wr_error) begin
              error <= 1'b1;
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else if (compute_q_group_idx == 5'(TOP_GROUPS - 1)) begin
              top_state <= TOP_ST_COMPUTE_COMPLETE;
            end else begin
              compute_q_group_idx      <= compute_q_group_idx + 1'b1;
              compute_q_idx            <= {compute_q_group_idx + 1'b1, 3'b000};
              compute_kv_tile_idx      <= '0;
              compute_kv_tile_base_idx <= 8'd0;
              compute_kv_row_idx       <= '0;
              compute_q_context_idx    <= '0;
              compute_init_context_idx <= '0;
              compute_buffer_wait_q    <= '0;
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
                      stride_bytes[0] ^ row_engine_busy ^
                      scheduler_q_group[0] ^ scheduler_kv_tile[0] ^
                      scheduler_q_context[0] ^ scheduler_kv_row[0] ^
                      scheduler_score_last ^ scheduler_tile_done ^
                      scheduler_group_done;
endmodule
