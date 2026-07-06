`timescale 1ns/1ps
`default_nettype none

// baseline4 第一版系统顶层集成框架。
// Q/O SRAM 读写和 finalize ACC 窄读均接到 packed_compute_core 的真实 SRAM 端口。
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
    output wire          m_axi_bready
);

wire start_pulse;
wire soft_reset_pulse;
wire irq_enable;
wire irq_pending;
wire causal_enable_cfg;
wire [63:0] q_base_addr;
wire [63:0] k_base_addr;
wire [63:0] v_base_addr;
wire [63:0] o_base_addr;
wire [31:0] stride_bytes_cfg;
wire [31:0] neg_large_cfg;
wire [15:0] score_scale_cfg;
wire [1:0]  lowp_mode;
wire [5:0]  lowp_block_rows;
wire [63:0] q_scale_base_addr;
wire [63:0] k_scale_base_addr;
wire [63:0] v_scale_base_addr;
wire lowp_int8_mode;
wire [15:0] lowp_q_scale;
wire [15:0] lowp_k_scale;
wire [15:0] lowp_v_scale;
wire [15:0] effective_score_scale;
wire task_busy;
wire task_done_pulse;
wire task_error;
wire global_clear;
wire run_enable;
wire init_start;
wire [31:0] perf_read_data;
wire [4:0] perf_read_index;

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
wire dma_done_valid;
wire [1:0] dma_done_kind;
wire dma_done_page;
wire [7:0] dma_done_tag;
wire dma_done_error;
reg rd_done_pending_reg;
reg [1:0] rd_done_kind_reg;
reg rd_done_page_reg;
reg [7:0] rd_done_tag_reg;
reg rd_done_error_reg;
wire raw_dma_done_valid;
wire [1:0] raw_dma_done_kind;
wire raw_dma_done_page;
wire [7:0] raw_dma_done_tag;
wire raw_dma_done_error;
wire dma_eng_done_valid;
wire [1:0] dma_eng_done_kind;
wire dma_eng_done_page;
wire [7:0] dma_eng_done_tag;
wire dma_eng_done_error;

wire dma_rd_valid;
wire dma_rd_ready;
wire [1:0] dma_rd_kind;
wire dma_rd_page;
wire [127:0] dma_rd_data;
wire dma_rd_last;
wire [7:0] dma_rd_tag;
wire q_rd_ready;
wire k_rd_ready;
wire v_rd_ready;
wire dma_wr_valid;
wire dma_wr_ready;
wire [127:0] dma_wr_data;
wire [15:0] dma_wr_strb;
wire dma_wr_last;

wire active_q_page;
wire active_k_page;
wire active_v_page;
wire [4:0] active_q_group;
wire [4:0] active_kv_tile;
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
wire [7:0] score_user_token;
wire [2:0] score_context;
wire score_last;
wire complete_valid;
wire [2:0] complete_context;
wire [7:0] complete_user_token;
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
wire compute_idle;
wire fin_acc_req_valid;
wire fin_acc_req_ready;
wire [2:0] fin_acc_req_context;
wire [1:0] fin_acc_req_quarter;
wire [2:0] fin_acc_req_pair;
wire fin_acc_rsp_valid;
wire signed [95:0] fin_acc_rsp_data;

assign irq = irq_enable && irq_pending;
assign lowp_int8_mode = (lowp_mode == 2'd1);

// bonus7: effective score scale with full-precision triple product.
// score_scale_cfg, lowp_q_scale, lowp_k_scale are all Q0.16.
// Verilog's self-determined multiplication width is max(L(op1),L(op2)),
// so $signed(16b)*$signed(16b)*$signed(16b) truncates the intermediate
// to 32 bits. Force 64-bit context to preserve the full 48-bit product.
wire signed [63:0] scale_step1;
wire signed [63:0] scale_triple_product;
wire [15:0] effective_score_scale_int8;
assign scale_step1 = $signed({48'd0, score_scale_cfg}) * $signed(lowp_q_scale);
assign scale_triple_product = scale_step1 * $signed(lowp_k_scale);
assign effective_score_scale_int8 = scale_triple_product[47:32];  // Q0.48 -> Q0.16

assign effective_score_scale = lowp_int8_mode ?
    effective_score_scale_int8 :
    score_scale_cfg;

assign raw_dma_done_valid = dma_eng_done_valid;
assign raw_dma_done_kind  = dma_eng_done_kind;
assign raw_dma_done_page  = dma_eng_done_page;
assign raw_dma_done_tag   = dma_eng_done_tag;
assign raw_dma_done_error = dma_eng_done_error;

wire rd_adapter_done = ((rd_done_kind_reg == 2'd0) && q_load_done) ||
                       ((rd_done_kind_reg == 2'd1) && k_load_done) ||
                       ((rd_done_kind_reg == 2'd2) && v_load_done);
wire raw_rd_adapter_done = ((raw_dma_done_kind == 2'd0) && q_load_done) ||
                           ((raw_dma_done_kind == 2'd1) && k_load_done) ||
                           ((raw_dma_done_kind == 2'd2) && v_load_done);

assign dma_done_valid = rd_done_pending_reg ? rd_adapter_done :
                        (raw_dma_done_valid &&
                         ((raw_dma_done_kind == 2'd3) || raw_rd_adapter_done));
assign dma_done_kind  = rd_done_pending_reg ? rd_done_kind_reg  : raw_dma_done_kind;
assign dma_done_page  = rd_done_pending_reg ? rd_done_page_reg  : raw_dma_done_page;
assign dma_done_tag   = rd_done_pending_reg ? rd_done_tag_reg   : raw_dma_done_tag;
assign dma_done_error = rd_done_pending_reg ? rd_done_error_reg : raw_dma_done_error;

assign dma_rd_ready = ((dma_rd_kind == 2'd0) && q_rd_ready) ||
                      ((dma_rd_kind == 2'd1) && k_rd_ready) ||
                      ((dma_rd_kind == 2'd2) && v_rd_ready);
assign perf_read_index = (s_axil_araddr[11:0] == 12'h040) ? 5'd0 : s_axil_araddr[6:2];

always @(posedge clk) begin
    if (!rst_n) begin
        rd_done_pending_reg <= 1'b0;
        rd_done_kind_reg <= 2'd0;
        rd_done_page_reg <= 1'b0;
        rd_done_tag_reg <= 8'd0;
        rd_done_error_reg <= 1'b0;
    end else begin
        if (rd_done_pending_reg && rd_adapter_done)
            rd_done_pending_reg <= 1'b0;
        if (raw_dma_done_valid && (raw_dma_done_kind != 2'd3) && !raw_rd_adapter_done) begin
            rd_done_pending_reg <= 1'b1;
            rd_done_kind_reg <= raw_dma_done_kind;
            rd_done_page_reg <= raw_dma_done_page;
            rd_done_tag_reg <= raw_dma_done_tag;
            rd_done_error_reg <= raw_dma_done_error;
        end
    end
end

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
    .q_base_addr(q_base_addr), .k_base_addr(k_base_addr),
    .v_base_addr(v_base_addr), .o_base_addr(o_base_addr),
    .stride_bytes(stride_bytes_cfg), .neg_large(neg_large_cfg),
    .score_scale(score_scale_cfg),
    .lowp_mode(lowp_mode), .lowp_block_rows(lowp_block_rows),
    .q_scale_base_addr(q_scale_base_addr),
    .k_scale_base_addr(k_scale_base_addr),
    .v_scale_base_addr(v_scale_base_addr),
    .active_q_group(active_q_group), .active_kv_tile(active_kv_tile),
    .lowp_q_scale(lowp_q_scale), .lowp_k_scale(lowp_k_scale),
    .lowp_v_scale(lowp_v_scale),
    .task_busy(task_busy),
    .task_done(task_done_pulse), .task_error(task_error),
    .perf_read_data(perf_read_data)
);

task_ctrl u_task (
    .clk(clk), .rst_n(rst_n), .start_pulse(start_pulse),
    .soft_reset_pulse(soft_reset_pulse), .init_done(1'b1),
    .run_done(sched_done || pm_done), .all_idle(!pm_busy && !o_store_busy),
    .error_in(pm_error || k_load_error || v_load_error || fin_error_zero_l),
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
    .busy(pm_busy), .done(pm_done), .error(pm_error),
    .update_state_idle(compute_idle),
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
    .lowp_int8_mode(lowp_int8_mode)
);

dma_engine u_dma (
    .clk(clk), .rst_n(rst_n), .cmd_valid(pm_cmd_valid), .cmd_ready(pm_cmd_ready),
    .cmd_kind(pm_cmd_kind), .cmd_page(pm_cmd_page), .cmd_base_addr(pm_cmd_base_addr),
    .cmd_bytes(pm_cmd_bytes), .cmd_tag(pm_cmd_tag),
    .rd_valid(dma_rd_valid), .rd_ready(dma_rd_ready), .rd_kind(dma_rd_kind),
    .rd_page(dma_rd_page), .rd_data(dma_rd_data), .rd_last(dma_rd_last), .rd_tag(dma_rd_tag),
    .wr_valid(dma_wr_valid), .wr_ready(dma_wr_ready), .wr_data(dma_wr_data),
    .wr_strb(dma_wr_strb), .wr_last(dma_wr_last),
    .done_valid(dma_eng_done_valid), .done_kind(dma_eng_done_kind), .done_page(dma_eng_done_page),
    .done_tag(dma_eng_done_tag), .done_error(dma_eng_done_error),
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

q_load_store_adapter u_q_adapter (
    .clk(clk), .rst_n(rst_n), .lowp_int8_mode(lowp_int8_mode),
    .q_load_start(q_load_start), .q_load_page(active_q_page),
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
    .clk(clk), .rst_n(rst_n), .start(k_load_start), .page(pm_cmd_page),
    .busy(), .done(k_load_done), .in_valid(dma_rd_valid && (dma_rd_kind == 2'd1)),
    .in_ready(k_rd_ready), .in_data(dma_rd_data), .in_last(dma_rd_last),
    .k_rw_valid(k_rw_valid), .k_rw_write(), .k_rw_pair(k_rw_pair),
    .k_rw_addr(k_rw_addr), .k_rw_wmask(k_rw_wmask), .k_rw_data(k_rw_data),
    .error(k_load_error),
    .lowp_int8_mode(lowp_int8_mode)
);

v_load_adapter u_v_adapter (
    .clk(clk), .rst_n(rst_n), .start(v_load_start), .page(pm_cmd_page),
    .busy(), .done(v_load_done), .in_valid(dma_rd_valid && (dma_rd_kind == 2'd2)),
    .in_ready(v_rd_ready), .in_data(dma_rd_data), .in_last(dma_rd_last),
    .v_rw_valid(v_rw_valid), .v_rw_write(), .v_rw_pair(v_rw_pair),
    .v_rw_addr(v_rw_addr), .v_rw_wmask(v_rw_wmask), .v_rw_data(v_rw_data),
    .error(v_load_error),
    .lowp_int8_mode(lowp_int8_mode), .lowp_v_scale(lowp_v_scale)
);

score_scheduler u_sched (
    .clk(clk), .rst_n(rst_n), .start(init_start), .run_enable(run_enable),
    .busy(), .done(sched_done), .q_group_ready(q_group_ready), .kv_tile_ready(kv_tile_ready),
    .active_q_page(active_q_page), .active_k_page(active_k_page), .active_v_page(active_v_page),
    .active_q_group(active_q_group), .active_kv_tile(active_kv_tile),
    .tile_done(sched_tile_done), .group_done(sched_group_done),
    .init_valid(init_valid), .init_ready(init_ready), .init_context(init_context),
    .score_valid(score_valid), .score_ready(score_ready), .score_q_page(score_q_page),
    .score_q_row(score_q_row), .score_k_page(score_k_page), .score_k_row(score_k_row),
    .score_v_page(score_v_page), .score_v_row(score_v_row), .score_m_old(score_m_old),
    .score_scale(effective_score_scale), .score_user_token(score_user_token),
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
    .clk(clk), .rst_n(rst_n),
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
    .score_scale(effective_score_scale), .score_user_token(score_user_token),
    .score_context(score_context), .score_last(score_last),
    .complete_valid(complete_valid), .complete_context(complete_context),
    .complete_user_token(complete_user_token), .complete_last(complete_last),
    .complete_m(complete_m), .complete_l(complete_l), .token_fifo_occupancy(token_fifo_occupancy),
    .fin_acc_req_valid(fin_acc_req_valid), .fin_acc_req_ready(fin_acc_req_ready),
    .fin_acc_req_context(fin_acc_req_context), .fin_acc_req_quarter(fin_acc_req_quarter),
    .fin_acc_req_pair(fin_acc_req_pair), .fin_acc_rsp_valid(fin_acc_rsp_valid),
    .fin_acc_rsp_data(fin_acc_rsp_data),
    .compute_idle(compute_idle)
);

finalize_cluster u_finalize (
    .clk(clk), .rst_n(rst_n), .req_valid(fin_req_valid), .req_ready(fin_req_ready),
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
