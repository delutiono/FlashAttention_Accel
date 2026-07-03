`timescale 1ns/1ps
`default_nettype none

// FlashAttention accelerator top-level with 7 bonus features:
//   Padding Mask, Q6.10/Q4.12, S=512, DMA Task Queue,
//   AXI4-Stream, Dropout, Multi-head
module fa_top (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [11:0]   s_axil_awaddr,
    input  wire          s_axil_awvalid,
    output wire          s_axil_awready,
    input  wire [31:0]   s_axil_wdata,
    input  wire [3:0]    s_axil_wstrb,
    input  wire          s_axil_wvalid,
    output wire          s_axil_wready,
    output wire [1:0]    s_axil_bresp,
    output wire          s_axil_bvalid,
    input  wire          s_axil_bready,
    input  wire [11:0]   s_axil_araddr,
    input  wire          s_axil_arvalid,
    output wire          s_axil_arready,
    output wire [31:0]   s_axil_rdata,
    output wire [1:0]    s_axil_rresp,
    output wire          s_axil_rvalid,
    input  wire          s_axil_rready,
    output wire          irq,

    output wire [63:0]   m_axi_araddr,
    output wire [7:0]    m_axi_arlen,
    output wire [2:0]    m_axi_arsize,
    output wire [1:0]    m_axi_arburst,
    output wire          m_axi_arvalid,
    input  wire          m_axi_arready,
    input  wire [127:0]  m_axi_rdata,
    input  wire [1:0]    m_axi_rresp,
    input  wire          m_axi_rlast,
    input  wire          m_axi_rvalid,
    output wire          m_axi_rready,
    output wire [63:0]   m_axi_awaddr,
    output wire [7:0]    m_axi_awlen,
    output wire [2:0]    m_axi_awsize,
    output wire [1:0]    m_axi_awburst,
    output wire          m_axi_awvalid,
    input  wire          m_axi_awready,
    output wire [127:0]  m_axi_wdata,
    output wire [15:0]   m_axi_wstrb,
    output wire          m_axi_wlast,
    output wire          m_axi_wvalid,
    input  wire          m_axi_wready,
    input  wire [1:0]    m_axi_bresp,
    input  wire          m_axi_bvalid,
    output wire          m_axi_bready,

    // AXI4-Stream slave (input Q/K/V)
    input  wire          s_axis_tvalid,
    output wire          s_axis_tready,
    input  wire [127:0]  s_axis_tdata,
    input  wire [15:0]   s_axis_tkeep,
    input  wire [1:0]    s_axis_tuser,
    input  wire          s_axis_tlast,

    // AXI4-Stream master (output O)
    output wire          m_axis_tvalid,
    input  wire          m_axis_tready,
    output wire [127:0]  m_axis_tdata,
    output wire [15:0]   m_axis_tkeep,
    output wire          m_axis_tlast
);

wire start_pulse;
wire soft_reset_pulse;
wire irq_enable;
wire irq_pending;
wire causal_enable_cfg;
wire [1:0]  format_sel_cfg;
wire [63:0] q_base_addr;
wire [63:0] k_base_addr;
wire [63:0] v_base_addr;
wire [63:0] o_base_addr;
wire [31:0] stride_bytes_cfg;
wire [5:0]  seq_len_cfg;
wire [7:0]  valid_len_cfg;
wire [31:0] neg_large_cfg;
wire [15:0] score_scale_cfg;
wire task_busy;
wire task_done_pulse;
wire task_error;
wire task_chain_enable;
wire task_queue_not_empty;
wire task_dequeue;
wire global_clear;
wire run_enable;
wire init_start;
wire [31:0] perf_read_data;
wire [4:0] perf_read_index;

// Bonus: AXI4-Stream, Dropout, Multi-head
wire stream_en;
wire dropout_en;
wire [31:0] dropout_seed;
wire [15:0] dropout_prob;
wire [2:0]  num_heads;
wire [31:0] head_stride;

wire pm_busy;
wire pm_done;
wire pm_error;
wire pm_cmd_valid;
wire pm_cmd_ready;
wire [1:0] pm_cmd_kind;
wire pm_cmd_page;
wire [63:0] pm_cmd_base_addr;
wire [15:0] pm_cmd_bytes;
wire [7:0] pm_cmd_tag;

// DMA engine outputs
wire dma_eng_rd_valid;
wire dma_eng_rd_ready;
wire [1:0] dma_eng_rd_kind;
wire dma_eng_rd_page;
wire [127:0] dma_eng_rd_data;
wire dma_eng_rd_last;
wire [7:0] dma_eng_rd_tag;
wire dma_eng_wr_valid;
wire dma_eng_wr_ready;
wire [127:0] dma_eng_wr_data;
wire [15:0] dma_eng_wr_strb;
wire dma_eng_wr_last;
wire dma_eng_done_valid;
wire [1:0] dma_eng_done_kind;
wire dma_eng_done_page;
wire [7:0] dma_eng_done_tag;
wire dma_eng_done_error;

// Stream adapter outputs
wire strm_rd_valid;
wire strm_rd_ready;
wire [1:0] strm_rd_kind;
wire strm_rd_page;
wire [127:0] strm_rd_data;
wire strm_rd_last;
wire [7:0] strm_rd_tag;
wire strm_wr_valid;
wire strm_wr_ready;
wire [127:0] strm_wr_data;
wire [15:0] strm_wr_strb;
wire strm_wr_last;
wire strm_done_valid;
wire [1:0] strm_done_kind;
wire strm_done_page;
wire [7:0] strm_done_tag;
wire strm_done_error;

// Final (muxed) DMA interface signals
wire dma_rd_valid;
wire dma_rd_ready;
wire [1:0] dma_rd_kind;
wire dma_rd_page;
wire [127:0] dma_rd_data;
wire dma_rd_last;
wire [7:0] dma_rd_tag;
wire dma_wr_valid;
wire dma_wr_ready;
wire [127:0] dma_wr_data;
wire [15:0] dma_wr_strb;
wire dma_wr_last;
wire dma_done_valid;
wire [1:0] dma_done_kind;
wire dma_done_page;
wire [7:0] dma_done_tag;
wire dma_done_error;

wire q_rd_ready;
wire k_rd_ready;
wire v_rd_ready;

wire active_q_page;
wire active_k_page;
wire active_v_page;
wire [5:0] active_q_group;
wire [5:0] active_kv_tile;
wire q_group_ready;
wire kv_tile_ready;
wire q_load_start;
wire k_load_start;
wire v_load_start;
wire o_store_start;
wire finalize_start;
wire sched_tile_done;
wire sched_group_done;
wire sched_done;

wire q_load_done;
wire k_load_done;
wire v_load_done;
wire k_load_error;
wire v_load_error;
wire q_rw_valid;
wire q_rw_write;
wire [1:0] q_rw_pair;
wire [4:0] q_rw_addr;
wire [15:0] q_rw_wmask;
wire [127:0] q_rw_wdata;
wire q_rw_rvalid;
wire [127:0] q_rw_rdata;
wire o_store_done;
wire o_store_busy;

wire k_rw_valid;
wire [1:0] k_rw_pair;
wire [4:0] k_rw_addr;
wire [15:0] k_rw_wmask;
wire [127:0] k_rw_data;
wire v_rw_valid;
wire v_rw_pair;
wire [5:0] v_rw_addr;
wire [15:0] v_rw_wmask;
wire [127:0] v_rw_data;

wire init_valid;
wire init_ready;
wire [2:0] init_context;
wire score_valid;
wire score_ready;
wire score_q_page;
wire [2:0] score_q_row;
wire score_k_page;
wire [2:0] score_k_row;
wire score_v_page;
wire [2:0] score_v_row;
wire signed [31:0] score_m_old;
wire [9:0] score_user_token;
wire [2:0] score_context;
wire score_last;
wire complete_valid;
wire [2:0] complete_context;
wire [9:0] complete_user_token;
wire complete_last;
wire signed [31:0] complete_m;
wire signed [47:0] complete_l;
wire [3:0] token_fifo_occupancy;

wire fin_req_valid;
wire fin_req_ready;
wire [2:0] fin_req_context;
wire fin_req_q_page;
wire [2:0] fin_req_row;
wire signed [31:0] fin_req_m;
wire signed [47:0] fin_req_l;
wire fin_o_valid;
wire fin_o_ready;
wire fin_o_page;
wire [2:0] fin_o_row;
wire fin_o_half;
wire [1:0] fin_o_pair;
wire [127:0] fin_o_data;
wire fin_done_valid;
wire [2:0] fin_done_context;
wire [2:0] fin_done_row;
wire fin_error_zero_l;
wire fin_acc_req_valid;
wire fin_acc_req_ready;
wire [2:0] fin_acc_req_context;
wire [1:0] fin_acc_req_quarter;
wire [2:0] fin_acc_req_pair;
wire fin_acc_rsp_valid;
wire signed [95:0] fin_acc_rsp_data;

assign irq = irq_enable && irq_pending;

assign dma_rd_valid  = stream_en ? strm_rd_valid  : dma_eng_rd_valid;
assign dma_rd_kind   = stream_en ? strm_rd_kind   : dma_eng_rd_kind;
assign dma_rd_page   = stream_en ? strm_rd_page   : dma_eng_rd_page;
assign dma_rd_data   = stream_en ? strm_rd_data   : dma_eng_rd_data;
assign dma_rd_last   = stream_en ? strm_rd_last   : dma_eng_rd_last;
assign dma_rd_tag    = stream_en ? strm_rd_tag    : dma_eng_rd_tag;
// Write data: from adapter (dma_wr_* or strm_wr_*) → to DMA engine input
assign dma_eng_wr_valid = stream_en ? strm_wr_valid : dma_wr_valid;
assign dma_eng_wr_data  = stream_en ? strm_wr_data  : dma_wr_data;
assign dma_eng_wr_strb  = stream_en ? strm_wr_strb  : dma_wr_strb;
assign dma_eng_wr_last  = stream_en ? strm_wr_last  : dma_wr_last;
assign dma_done_valid = stream_en ? strm_done_valid : dma_eng_done_valid;
assign dma_done_kind  = stream_en ? strm_done_kind  : dma_eng_done_kind;
assign dma_done_page  = stream_en ? strm_done_page  : dma_eng_done_page;
assign dma_done_tag   = stream_en ? strm_done_tag   : dma_eng_done_tag;
assign dma_done_error = stream_en ? strm_done_error : dma_eng_done_error;

// Read ready: from adapters → to DMA engine or stream adapter
assign dma_eng_rd_ready = stream_en ? 1'b0 : dma_rd_ready;
assign strm_rd_ready    = stream_en ? dma_rd_ready : 1'b0;
// Write ready: from DMA engine output → to adapter (dma or stream)
assign dma_wr_ready  = stream_en ? 1'b0 : dma_eng_wr_ready;
assign strm_wr_ready = stream_en ? dma_eng_wr_ready : 1'b0;

assign dma_rd_ready = ((dma_rd_kind == 2'd0) && q_rd_ready) ||
                      ((dma_rd_kind == 2'd1) && k_rd_ready) ||
                      ((dma_rd_kind == 2'd2) && v_rd_ready);
assign perf_read_index = (s_axil_araddr[11:0] == 12'h040) ? 5'd0 : s_axil_araddr[6:2];

axi_lite_regs u_regs (
    .clk(clk), .rst_n(rst_n),
    .s_awaddr(s_axil_awaddr), .s_awvalid(s_axil_awvalid), .s_awready(s_axil_awready),
    .s_wdata(s_axil_wdata), .s_wstrb(s_axil_wstrb), .s_wvalid(s_axil_wvalid),
    .s_wready(s_axil_wready), .s_bresp(s_axil_bresp), .s_bvalid(s_axil_bvalid),
    .s_bready(s_axil_bready), .s_araddr(s_axil_araddr), .s_arvalid(s_axil_arvalid),
    .s_arready(s_axil_arready), .s_rdata(s_axil_rdata), .s_rresp(s_axil_rresp),
    .s_rvalid(s_axil_rvalid), .s_rready(s_axil_rready),
    .start_pulse(start_pulse), .soft_reset_pulse(soft_reset_pulse),
    .irq_enable(irq_enable), .irq_pending(irq_pending),
    .causal_enable(causal_enable_cfg),
    .format_sel(format_sel_cfg),
    .q_base_addr(q_base_addr), .k_base_addr(k_base_addr),
    .v_base_addr(v_base_addr), .o_base_addr(o_base_addr),
    .stride_bytes(stride_bytes_cfg), .seq_len(seq_len_cfg), .valid_len(valid_len_cfg),
    .neg_large(neg_large_cfg), .score_scale(score_scale_cfg),
    .task_chain_enable(task_chain_enable),
    .task_queue_not_empty(task_queue_not_empty), .task_dequeue(task_dequeue),
    .task_busy(task_busy), .task_done(task_done_pulse), .task_error(task_error),
    .perf_read_data(perf_read_data),
    .stream_en(stream_en),
    .dropout_en(dropout_en), .dropout_seed(dropout_seed), .dropout_prob(dropout_prob),
    .num_heads(num_heads), .head_stride(head_stride)
);

task_ctrl u_task (
    .clk(clk), .rst_n(rst_n), .start_pulse(start_pulse),
    .soft_reset_pulse(soft_reset_pulse), .init_done(1'b1),
    .run_done(sched_done || pm_done), .all_idle(!pm_busy && !o_store_busy),
    .error_in(pm_error || k_load_error || v_load_error || fin_error_zero_l),
    .task_chain_enable(task_chain_enable), .task_queue_not_empty(task_queue_not_empty),
    .task_busy(task_busy), .task_done_pulse(task_done_pulse),
    .task_error(task_error), .global_clear(global_clear),
    .run_enable(run_enable), .init_start(init_start)
);

perf_counters u_perf (
    .clk(clk), .rst_n(rst_n), .clear(global_clear), .enable(task_busy),
    .score_issue(score_valid && score_ready), .update_quarter(1'b0),
    .update_complete(complete_valid), .dma_rd_busy(m_axi_arvalid || m_axi_rvalid),
    .dma_wr_busy(m_axi_awvalid || m_axi_wvalid), .finalize_busy(fin_req_valid || fin_o_valid),
    .stall_q_page(!q_group_ready && run_enable), .stall_kv_page(!kv_tile_ready && run_enable),
    .stall_fifo(token_fifo_occupancy == 4'd8), .read_index(perf_read_index),
    .read_data(perf_read_data)
);

page_manager u_page (
    .clk(clk), .rst_n(rst_n), .start(init_start), .run_enable(run_enable),
    .num_groups(seq_len_cfg),
    .busy(pm_busy), .done(pm_done), .error(pm_error),
    .cmd_valid(pm_cmd_valid), .cmd_ready(pm_cmd_ready), .cmd_kind(pm_cmd_kind),
    .cmd_page(pm_cmd_page), .cmd_base_addr(pm_cmd_base_addr),
    .cmd_bytes(pm_cmd_bytes), .cmd_tag(pm_cmd_tag),
    .dma_done_valid(dma_done_valid), .dma_done_tag(dma_done_tag),
    .dma_done_error(dma_done_error), .q_base_addr(q_base_addr),
    .k_base_addr(k_base_addr), .v_base_addr(v_base_addr), .o_base_addr(o_base_addr),
    .active_q_page(active_q_page), .active_k_page(active_k_page), .active_v_page(active_v_page),
    .active_q_group(active_q_group), .active_kv_tile(active_kv_tile),
    .q_group_ready(q_group_ready), .kv_tile_ready(kv_tile_ready),
    .scheduler_tile_done(sched_tile_done), .scheduler_group_done(sched_group_done),
    .q_load_start(q_load_start), .k_load_start(k_load_start), .v_load_start(v_load_start),
    .o_store_start(o_store_start), .finalize_start(finalize_start),
    .task_chain_enable(task_chain_enable), .task_queue_not_empty(task_queue_not_empty),
    .task_dequeue(task_dequeue),
    .num_heads(num_heads), .head_stride(head_stride)
);

dma_engine u_dma (
    .clk(clk), .rst_n(rst_n), .cmd_valid(pm_cmd_valid), .cmd_ready(pm_cmd_ready),
    .cmd_kind(pm_cmd_kind), .cmd_page(pm_cmd_page), .cmd_base_addr(pm_cmd_base_addr),
    .cmd_bytes(pm_cmd_bytes), .cmd_tag(pm_cmd_tag),
    .rd_valid(dma_eng_rd_valid), .rd_ready(dma_eng_rd_ready),
    .rd_kind(dma_eng_rd_kind), .rd_page(dma_eng_rd_page),
    .rd_data(dma_eng_rd_data), .rd_last(dma_eng_rd_last), .rd_tag(dma_eng_rd_tag),
    .wr_valid(dma_eng_wr_valid), .wr_ready(dma_eng_wr_ready),
    .wr_data(dma_eng_wr_data), .wr_strb(dma_eng_wr_strb), .wr_last(dma_eng_wr_last),
    .done_valid(dma_eng_done_valid), .done_kind(dma_eng_done_kind),
    .done_page(dma_eng_done_page), .done_tag(dma_eng_done_tag),
    .done_error(dma_eng_done_error),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
);

axi_stream_data_adapter u_stream (
    .clk(clk), .rst_n(rst_n), .stream_en(stream_en),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tuser(s_axis_tuser), .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tlast(m_axis_tlast),
    .rd_valid(strm_rd_valid), .rd_ready(strm_rd_ready),
    .rd_kind(strm_rd_kind), .rd_page(strm_rd_page),
    .rd_data(strm_rd_data), .rd_last(strm_rd_last), .rd_tag(strm_rd_tag),
    .wr_valid(strm_wr_valid), .wr_ready(strm_wr_ready),
    .wr_data(strm_wr_data), .wr_strb(strm_wr_strb), .wr_last(strm_wr_last),
    .pm_cmd_valid(pm_cmd_valid), .pm_cmd_kind(pm_cmd_kind),
    .pm_cmd_page(pm_cmd_page), .pm_cmd_tag(pm_cmd_tag),
    .done_valid(strm_done_valid), .done_kind(strm_done_kind),
    .done_page(strm_done_page), .done_tag(strm_done_tag),
    .done_error(strm_done_error)
);

q_load_store_adapter u_q_adapter (
    .clk(clk), .rst_n(rst_n), .q_load_start(q_load_start), .q_load_page(active_q_page),
    .q_load_done(q_load_done), .q_rd_valid(dma_rd_valid && (dma_rd_kind == 2'd0)),
    .q_rd_ready(q_rd_ready), .q_rd_data(dma_rd_data), .q_rd_last(dma_rd_last),
    .o_store_start(o_store_start), .o_store_page(active_q_page),
    .o_store_busy(o_store_busy), .o_store_done(o_store_done),
    .o_wr_valid(dma_wr_valid), .o_wr_ready(dma_wr_ready), .o_wr_data(dma_wr_data),
    .o_wr_strb(dma_wr_strb), .o_wr_last(dma_wr_last),
    .fin_valid(fin_o_valid), .fin_ready(fin_o_ready), .fin_page(fin_o_page),
    .fin_row(fin_o_row), .fin_half(fin_o_half), .fin_pair(fin_o_pair), .fin_data(fin_o_data),
    .q_rw_valid(q_rw_valid), .q_rw_write(q_rw_write), .q_rw_pair(q_rw_pair),
    .q_rw_addr(q_rw_addr), .q_rw_wmask(q_rw_wmask), .q_rw_wdata(q_rw_wdata),
    .q_rw_rvalid(q_rw_rvalid), .q_rw_rdata(q_rw_rdata)
);

k_load_adapter u_k_adapter (
    .clk(clk), .rst_n(rst_n), .start(k_load_start), .page(dma_rd_page),
    .busy(), .done(k_load_done), .in_valid(dma_rd_valid && (dma_rd_kind == 2'd1)),
    .in_ready(k_rd_ready), .in_data(dma_rd_data), .in_last(dma_rd_last),
    .k_rw_valid(k_rw_valid), .k_rw_write(), .k_rw_pair(k_rw_pair),
    .k_rw_addr(k_rw_addr), .k_rw_wmask(k_rw_wmask), .k_rw_data(k_rw_data),
    .error(k_load_error)
);

v_load_adapter u_v_adapter (
    .clk(clk), .rst_n(rst_n), .start(v_load_start), .page(dma_rd_page),
    .busy(), .done(v_load_done), .in_valid(dma_rd_valid && (dma_rd_kind == 2'd2)),
    .in_ready(v_rd_ready), .in_data(dma_rd_data), .in_last(dma_rd_last),
    .v_rw_valid(v_rw_valid), .v_rw_write(), .v_rw_pair(v_rw_pair),
    .v_rw_addr(v_rw_addr), .v_rw_wmask(v_rw_wmask), .v_rw_data(v_rw_data),
    .error(v_load_error)
);

score_scheduler u_sched (
    .clk(clk), .rst_n(rst_n), .start(init_start), .run_enable(run_enable),
    .num_groups(seq_len_cfg),
    .busy(), .done(sched_done), .q_group_ready(q_group_ready), .kv_tile_ready(kv_tile_ready),
    .active_q_page(active_q_page), .active_k_page(active_k_page), .active_v_page(active_v_page),
    .active_q_group(active_q_group), .active_kv_tile(active_kv_tile),
    .tile_done(sched_tile_done), .group_done(sched_group_done),
    .init_valid(init_valid), .init_ready(init_ready), .init_context(init_context),
    .score_valid(score_valid), .score_ready(score_ready), .score_q_page(score_q_page),
    .score_q_row(score_q_row), .score_k_page(score_k_page), .score_k_row(score_k_row),
    .score_v_page(score_v_page), .score_v_row(score_v_row), .score_m_old(score_m_old),
    .score_scale(score_scale_cfg), .score_user_token(score_user_token),
    .score_context(score_context), .score_last(score_last),
    .complete_valid(complete_valid), .complete_context(complete_context),
    .complete_user_token(complete_user_token), .complete_last(complete_last),
    .complete_m(complete_m), .complete_l(complete_l),
    .finalize_req_valid(fin_req_valid), .finalize_req_ready(fin_req_ready),
    .finalize_req_context(fin_req_context), .finalize_req_q_page(fin_req_q_page),
    .finalize_req_row(fin_req_row), .finalize_req_m(fin_req_m), .finalize_req_l(fin_req_l),
    .finalize_done_valid(fin_done_valid), .finalize_done_context(fin_done_context)
);

packed_compute_core u_core (
    .clk(clk), .rst_n(rst_n), .valid_len(valid_len_cfg),
    .q_load_valid(1'b0), .q_load_pair(2'd0), .q_load_addr(5'd0),
    .q_load_wmask(16'd0), .q_load_data(128'd0),
    .q_ext_valid(q_rw_valid), .q_ext_write(q_rw_write), .q_ext_pair(q_rw_pair),
    .q_ext_addr(q_rw_addr), .q_ext_wmask(q_rw_wmask), .q_ext_wdata(q_rw_wdata),
    .q_ext_rvalid(q_rw_rvalid), .q_ext_rdata(q_rw_rdata),
    .k_load_valid(k_rw_valid), .k_load_pair(k_rw_pair), .k_load_addr(k_rw_addr),
    .k_load_wmask(k_rw_wmask), .k_load_data(k_rw_data),
    .v_load_valid(v_rw_valid), .v_load_pair(v_rw_pair), .v_load_addr(v_rw_addr),
    .v_load_wmask(v_rw_wmask), .v_load_data(v_rw_data),
    .init_valid(init_valid), .init_ready(init_ready), .init_context(init_context),
    .score_valid(score_valid), .score_ready(score_ready), .score_q_page(score_q_page),
    .score_q_row(score_q_row), .score_k_page(score_k_page), .score_k_row(score_k_row),
    .score_v_page(score_v_page), .score_v_row(score_v_row), .score_m_old(score_m_old),
    .score_scale(score_scale_cfg), .score_user_token(score_user_token),
    .score_context(score_context), .score_last(score_last),
    .score_dropout_en(dropout_en), .score_dropout_seed(dropout_seed),
    .score_dropout_prob(dropout_prob),
    .complete_valid(complete_valid), .complete_context(complete_context),
    .complete_user_token(complete_user_token), .complete_last(complete_last),
    .complete_m(complete_m), .complete_l(complete_l), .token_fifo_occupancy(token_fifo_occupancy),
    .fin_acc_req_valid(fin_acc_req_valid), .fin_acc_req_ready(fin_acc_req_ready),
    .fin_acc_req_context(fin_acc_req_context), .fin_acc_req_quarter(fin_acc_req_quarter),
    .fin_acc_req_pair(fin_acc_req_pair), .fin_acc_rsp_valid(fin_acc_rsp_valid),
    .fin_acc_rsp_data(fin_acc_rsp_data)
);

finalize_cluster u_finalize (
    .clk(clk), .rst_n(rst_n), .req_valid(fin_req_valid), .req_ready(fin_req_ready),
    .format_sel(format_sel_cfg),
    .req_context(fin_req_context), .req_q_page(fin_req_q_page), .req_q_row(fin_req_row),
    .req_l(fin_req_l), .acc_req_valid(fin_acc_req_valid), .acc_req_ready(fin_acc_req_ready),
    .acc_req_context(fin_acc_req_context), .acc_req_quarter(fin_acc_req_quarter),
    .acc_req_pair(fin_acc_req_pair), .acc_rsp_valid(fin_acc_rsp_valid),
    .acc_rsp_data(fin_acc_rsp_data),
    .o_valid(fin_o_valid), .o_ready(fin_o_ready), .o_page(fin_o_page),
    .o_row(fin_o_row), .o_half(fin_o_half), .o_pair(fin_o_pair),
    .o_data(fin_o_data), .o_last(), .done_valid(fin_done_valid),
    .done_context(fin_done_context), .done_row(fin_done_row),
    .error_zero_l(fin_error_zero_l)
);

endmodule

`default_nettype wire
