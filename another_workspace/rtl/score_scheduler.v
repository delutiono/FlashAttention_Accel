`timescale 1ns/1ps
`default_nettype none

// baseline4 固定 S=256、Q group=8、KV tile=8 的保守 score 调度器。
// 顺序产生合法 causal score，并在每个 group 完成后依次发 8 个 finalize request。
module score_scheduler (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,
    input  wire                run_enable,
    output wire                busy,
    output reg                 done,

    input  wire                q_group_ready,
    input  wire                kv_tile_ready,
    input  wire                active_q_page,
    input  wire                active_k_page,
    input  wire                active_v_page,
    input  wire [4:0]          active_q_group,
    input  wire [4:0]          active_kv_tile,
    output reg                 tile_done,
    output reg                 group_done,

    output reg                 init_valid,
    input  wire                init_ready,
    output reg [2:0]           init_context,

    output reg                 score_valid,
    input  wire                score_ready,
    output reg                 score_q_page,
    output reg [2:0]           score_q_row,
    output reg                 score_k_page,
    output reg [2:0]           score_k_row,
    output reg                 score_v_page,
    output reg [2:0]           score_v_row,
    output reg signed [31:0]   score_m_old,
    input  wire [15:0]         score_scale,
    output reg [7:0]           score_user_token,
    output reg [2:0]           score_context,
    output reg                 score_last,

    input  wire                complete_valid,
    input  wire [2:0]          complete_context,
    input  wire [7:0]          complete_user_token,
    input  wire                complete_last,
    input  wire signed [31:0]  complete_m,
    input  wire signed [47:0]  complete_l,

    output reg                 finalize_req_valid,
    input  wire                finalize_req_ready,
    output reg [2:0]           finalize_req_context,
    output reg                 finalize_req_q_page,
    output reg [2:0]           finalize_req_row,
    output reg signed [31:0]   finalize_req_m,
    output reg signed [47:0]   finalize_req_l,
    input  wire                finalize_done_valid,
    input  wire [2:0]          finalize_done_context
);

localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_INIT = 3'd1;
localparam [2:0] ST_WAIT = 3'd2;
localparam [2:0] ST_RUN  = 3'd3;
localparam [2:0] ST_DRAIN = 3'd4;
localparam [2:0] ST_FIN_REQ = 3'd5;
localparam [2:0] ST_FIN_WAIT = 3'd6;
localparam [2:0] ST_DONE = 3'd7;

reg [2:0] state_reg;
reg [2:0] init_idx_reg;
reg [2:0] ctx_issue_reg;
reg [2:0] kv_row_reg;
reg [2:0] fin_idx_reg;
reg [7:0] fin_pending_reg;
reg [7:0] pending_reg;
reg [7:0] issued_last_reg;
reg signed [31:0] m_mem [0:7];
reg signed [47:0] l_mem [0:7];
reg [7:0] token_counter_reg;
reg group_wait_drop_reg;
reg [4:0] run_q_group_reg;
reg [4:0] run_kv_tile_reg;

wire [7:0] global_q_row = {run_q_group_reg, ctx_issue_reg};
wire [7:0] global_k_row = {run_kv_tile_reg, kv_row_reg};
wire causal_ok = (global_k_row <= global_q_row);
wire issue_fire = score_valid && score_ready;
wire last_for_context = (run_kv_tile_reg == run_q_group_reg) &&
                        (kv_row_reg == ctx_issue_reg);

assign busy = (state_reg != ST_IDLE);

integer i;
always @(posedge clk) begin
    if (!rst_n) begin
        state_reg <= ST_IDLE;
        done <= 1'b0;
        tile_done <= 1'b0;
        group_done <= 1'b0;
        init_valid <= 1'b0;
        init_context <= 3'd0;
        score_valid <= 1'b0;
        score_q_page <= 1'b0;
        score_q_row <= 3'd0;
        score_k_page <= 1'b0;
        score_k_row <= 3'd0;
        score_v_page <= 1'b0;
        score_v_row <= 3'd0;
        score_m_old <= 32'sh8000_0000;
        score_user_token <= 8'd0;
        score_context <= 3'd0;
        score_last <= 1'b0;
        finalize_req_valid <= 1'b0;
        finalize_req_context <= 3'd0;
        finalize_req_q_page <= 1'b0;
        finalize_req_row <= 3'd0;
        finalize_req_m <= 32'sd0;
        finalize_req_l <= 48'sd0;
        init_idx_reg <= 3'd0;
        ctx_issue_reg <= 3'd0;
        kv_row_reg <= 3'd0;
        fin_idx_reg <= 3'd0;
        fin_pending_reg <= 8'd0;
        pending_reg <= 8'd0;
        issued_last_reg <= 8'd0;
        token_counter_reg <= 8'd0;
        group_wait_drop_reg <= 1'b0;
        run_q_group_reg <= 5'd0;
        run_kv_tile_reg <= 5'd0;
        for (i = 0; i < 8; i = i + 1) begin
            m_mem[i] <= 32'sh8000_0000;
            l_mem[i] <= 48'sd0;
        end
    end else begin
        done <= 1'b0;
        tile_done <= 1'b0;
        group_done <= 1'b0;

        if (score_valid && score_ready)
            score_valid <= 1'b0;
        if (finalize_req_valid && finalize_req_ready)
            finalize_req_valid <= 1'b0;

        if (complete_valid) begin
            m_mem[complete_context] <= complete_m;
            l_mem[complete_context] <= complete_l;
            if (pending_reg[complete_context])
                pending_reg[complete_context] <= 1'b0;
            if (complete_last)
                issued_last_reg[complete_context] <= 1'b1;
        end
        if (finalize_done_valid)
            fin_pending_reg[finalize_done_context] <= 1'b0;

        case (state_reg)
            ST_IDLE: begin
                if (start && run_enable) begin
                    init_idx_reg <= 3'd0;
                    token_counter_reg <= 8'd0;
                    issued_last_reg <= 8'd0;
                    fin_pending_reg <= 8'd0;
                    group_wait_drop_reg <= 1'b0;
                    for (i = 0; i < 8; i = i + 1) begin
                        m_mem[i] <= 32'sh8000_0000;
                        l_mem[i] <= 48'sd0;
                        pending_reg[i] <= 1'b0;
                    end
                    state_reg <= ST_INIT;
                end
            end
            ST_INIT: begin
                if (group_wait_drop_reg) begin
                    // 上一 group 的 O store 完成前 page manager 仍保持旧
                    // q/kv ready。必须观察两者都撤销后才能开始下一组，
                    // 否则会在 Q/O SRAM 写回期间重发上一 group。
                    init_valid <= 1'b0;
                    if (!q_group_ready && !kv_tile_ready)
                        group_wait_drop_reg <= 1'b0;
                end else begin
                    if (!init_valid) begin
                        init_valid <= 1'b1;
                        init_context <= init_idx_reg;
                    end
                    if (init_valid && init_ready) begin
                        init_valid <= 1'b0;
                        init_idx_reg <= init_idx_reg + 3'd1;
                        if (init_idx_reg == 3'd7)
                            state_reg <= ST_WAIT;
                    end
                end
            end
            ST_WAIT: begin
                if (q_group_ready && kv_tile_ready) begin
                    ctx_issue_reg <= 3'd0;
                    kv_row_reg <= 3'd0;
                    run_q_group_reg <= active_q_group;
                    run_kv_tile_reg <= active_kv_tile;
                    state_reg <= ST_RUN;
                end
            end
            ST_RUN: begin
                if (!score_valid && !pending_reg[ctx_issue_reg]) begin
                    if (causal_ok) begin
                        score_valid <= 1'b1;
                        score_q_page <= active_q_page;
                        score_q_row <= ctx_issue_reg;
                        score_k_page <= active_k_page;
                        score_k_row <= kv_row_reg;
                        score_v_page <= active_v_page;
                        score_v_row <= kv_row_reg;
                        score_m_old <= m_mem[ctx_issue_reg];
                        score_user_token <= token_counter_reg;
                        score_context <= ctx_issue_reg;
                        score_last <= last_for_context;
                    end
                    if (!causal_ok) begin
                        ctx_issue_reg <= ctx_issue_reg + 3'd1;
                        if (ctx_issue_reg == 3'd7) begin
                            ctx_issue_reg <= 3'd0;
                            kv_row_reg <= kv_row_reg + 3'd1;
                            if (kv_row_reg == 3'd7)
                                state_reg <= ST_DRAIN;
                        end
                    end
                end
                if (issue_fire) begin
                    pending_reg[score_context] <= 1'b1;
                    token_counter_reg <= token_counter_reg + 8'd1;
                    ctx_issue_reg <= ctx_issue_reg + 3'd1;
                    if (ctx_issue_reg == 3'd7) begin
                        ctx_issue_reg <= 3'd0;
                        kv_row_reg <= kv_row_reg + 3'd1;
                        if (kv_row_reg == 3'd7)
                            state_reg <= ST_DRAIN;
                    end
                end
            end
            ST_DRAIN: begin
                if (pending_reg == 8'd0) begin
                    if (run_kv_tile_reg == run_q_group_reg) begin
                        tile_done <= 1'b1;
                        fin_idx_reg <= 3'd0;
                        state_reg <= ST_FIN_REQ;
                    end else if (kv_tile_ready) begin
                        // 通知 page manager 释放当前 tile，但必须等待
                        // kv_tile_ready 先拉低再进入 ST_WAIT。否则双方在同一
                        // 时钟沿采到旧的 ready=1，会在下一 tile 装载期间误发
                        // 旧 tile score，造成 V load/update 端口冲突。
                        tile_done <= 1'b1;
                    end else begin
                        state_reg <= ST_WAIT;
                    end
                end
            end
            ST_FIN_REQ: begin
                if (!finalize_req_valid) begin
                    finalize_req_valid <= 1'b1;
                    finalize_req_context <= fin_idx_reg;
                    finalize_req_q_page <= active_q_page;
                    finalize_req_row <= fin_idx_reg;
                    finalize_req_m <= m_mem[fin_idx_reg];
                    finalize_req_l <= l_mem[fin_idx_reg];
                    fin_pending_reg[fin_idx_reg] <= 1'b1;
                end
                if (finalize_req_valid && finalize_req_ready) begin
                    fin_idx_reg <= fin_idx_reg + 3'd1;
                    if (fin_idx_reg == 3'd7)
                        state_reg <= ST_FIN_WAIT;
                end
            end
            ST_FIN_WAIT: begin
                if (fin_pending_reg == 8'd0) begin
                    group_done <= 1'b1;
                    if (active_q_group == 5'd31)
                        state_reg <= ST_DONE;
                    else begin
                        group_wait_drop_reg <= 1'b1;
                        state_reg <= ST_INIT;
                    end
                end
            end
            ST_DONE: begin
                done <= 1'b1;
                state_reg <= ST_IDLE;
            end
            default: state_reg <= ST_IDLE;
        endcase
    end
end

endmodule

`default_nettype wire
