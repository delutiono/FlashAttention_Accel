`timescale 1ns/1ps
`default_nettype none

// Page manager with configurable sequence length (num_groups = S/8).
module page_manager (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        run_enable,
    input  wire [5:0]  num_groups,
    output wire        busy,
    output reg         done,
    output reg         error,

    output reg         cmd_valid,
    input  wire        cmd_ready,
    output reg [1:0]   cmd_kind,     // 0=Q load, 1=K load, 2=V load, 3=O store
    output reg         cmd_page,
    output reg [63:0]  cmd_base_addr,
    output reg [15:0]  cmd_bytes,
    output reg [7:0]   cmd_tag,
    input  wire        dma_done_valid,
    input  wire [7:0]  dma_done_tag,
    input  wire        dma_done_error,

    input  wire [63:0] q_base_addr,
    input  wire [63:0] k_base_addr,
    input  wire [63:0] v_base_addr,
    input  wire [63:0] o_base_addr,

    output reg         active_q_page,
    output reg         active_k_page,
    output reg         active_v_page,
    output reg [5:0]   active_q_group,
    output reg [5:0]   active_kv_tile,
    output wire        q_group_ready,
    output wire        kv_tile_ready,
    input  wire        scheduler_tile_done,
    input  wire        scheduler_group_done,

    output reg         q_load_start,
    output reg         k_load_start,
    output reg         v_load_start,
    output reg         o_store_start,
    output reg         finalize_start,

    input  wire        task_chain_enable,
    input  wire        task_queue_not_empty,
    output reg         task_dequeue
);

localparam [3:0] ST_IDLE   = 4'd0;
localparam [3:0] ST_Q_CMD  = 4'd1;
localparam [3:0] ST_Q_WAIT = 4'd2;
localparam [3:0] ST_K_CMD  = 4'd3;
localparam [3:0] ST_K_WAIT = 4'd4;
localparam [3:0] ST_V_CMD  = 4'd5;
localparam [3:0] ST_V_WAIT = 4'd6;
localparam [3:0] ST_RUN    = 4'd7;
localparam [3:0] ST_O_CMD  = 4'd8;
localparam [3:0] ST_O_WAIT = 4'd9;
localparam [3:0] ST_DONE   = 4'd10;
localparam [3:0] ST_NEXT_V_CMD  = 4'd11;
localparam [3:0] ST_NEXT_V_WAIT = 4'd12;
localparam [3:0] ST_NEXT_READY  = 4'd13;

localparam [2:0] PF_IDLE  = 3'd0;
localparam [2:0] PF_K_WAIT = 3'd1;
localparam [2:0] PF_K_READY = 3'd2;
localparam [2:0] PF_V_WAIT = 3'd3;
localparam [2:0] PF_READY = 3'd4;

reg [3:0] state_reg;
reg q_ready_reg;
reg kv_ready_reg;
reg [7:0] expect_tag_reg;
reg [2:0] prefetch_state_reg;
reg [5:0] prefetch_tile_reg;
reg       prefetch_page_reg;
reg [7:0] prefetch_expect_tag_reg;
reg       next_tile_pending_reg;

assign busy = (state_reg != ST_IDLE);
assign q_group_ready = q_ready_reg;
assign kv_tile_ready = kv_ready_reg;

function [63:0] add_group_offset;
    input [63:0] base;
    input [5:0] group_idx;
    begin
        add_group_offset = base + {48'd0, group_idx, 10'd0}; // 8 rows * 64 elem * 2B = 1024B
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        state_reg <= ST_IDLE;
        done <= 1'b0;
        error <= 1'b0;
        cmd_valid <= 1'b0;
        cmd_kind <= 2'd0;
        cmd_page <= 1'b0;
        cmd_base_addr <= 64'd0;
        cmd_bytes <= 16'd1024;
        cmd_tag <= 8'd0;
        active_q_page <= 1'b0;
        active_k_page <= 1'b0;
        active_v_page <= 1'b0;
        active_q_group <= 6'd0;
        active_kv_tile <= 6'd0;
        q_ready_reg <= 1'b0;
        kv_ready_reg <= 1'b0;
        expect_tag_reg <= 8'd0;
        q_load_start <= 1'b0;
        k_load_start <= 1'b0;
        v_load_start <= 1'b0;
        o_store_start <= 1'b0;
        finalize_start <= 1'b0;
        prefetch_state_reg <= PF_IDLE;
        prefetch_tile_reg <= 6'd0;
        prefetch_page_reg <= 1'b0;
        prefetch_expect_tag_reg <= 8'd0;
        next_tile_pending_reg <= 1'b0;
        task_dequeue <= 1'b0;
    end else begin
        done <= 1'b0;
        q_load_start <= 1'b0;
        k_load_start <= 1'b0;
        v_load_start <= 1'b0;
        o_store_start <= 1'b0;
        finalize_start <= 1'b0;
        task_dequeue <= 1'b0;

        if (dma_done_valid && dma_done_error)
            error <= 1'b1;

        if (cmd_valid && cmd_ready)
            cmd_valid <= 1'b0;

        case (state_reg)
            ST_IDLE: begin
                q_ready_reg <= 1'b0;
                kv_ready_reg <= 1'b0;
                prefetch_state_reg <= PF_IDLE;
                next_tile_pending_reg <= 1'b0;
                if (start && run_enable) begin
                    active_q_group <= 6'd0;
                    active_kv_tile <= 6'd0;
                    active_q_page <= 1'b0;
                    active_k_page <= 1'b0;
                    active_v_page <= 1'b0;
                    prefetch_tile_reg <= 6'd0;
                    prefetch_page_reg <= 1'b0;
                    prefetch_expect_tag_reg <= 8'd0;
                    error <= 1'b0;
                    state_reg <= ST_Q_CMD;
                end
            end
            ST_Q_CMD: begin
                if (!cmd_valid) begin
                    cmd_valid <= 1'b1;
                    cmd_kind <= 2'd0;
                    cmd_page <= active_q_page;
                    cmd_base_addr <= add_group_offset(q_base_addr, active_q_group);
                    cmd_bytes <= 16'd1024;
                    cmd_tag <= {2'd0, active_q_group};
                    expect_tag_reg <= {2'd0, active_q_group};
                    q_load_start <= 1'b1;
                    state_reg <= ST_Q_WAIT;
                end
            end
            ST_Q_WAIT: begin
                if (dma_done_valid && (dma_done_tag == expect_tag_reg)) begin
                    q_ready_reg <= !dma_done_error;
                    state_reg <= ST_K_CMD;
                end
            end
            ST_K_CMD: begin
                if (!cmd_valid) begin
                    cmd_valid <= 1'b1;
                    cmd_kind <= 2'd1;
                    cmd_page <= active_k_page;
                    cmd_base_addr <= add_group_offset(k_base_addr, active_kv_tile);
                    cmd_bytes <= 16'd1024;
                    cmd_tag <= 8'h40 | {2'd0, active_kv_tile};
                    expect_tag_reg <= 8'h40 | {2'd0, active_kv_tile};
                    k_load_start <= 1'b1;
                    state_reg <= ST_K_WAIT;
                end
            end
            ST_K_WAIT: begin
                if (dma_done_valid && (dma_done_tag == expect_tag_reg))
                    state_reg <= ST_V_CMD;
            end
            ST_V_CMD: begin
                if (!cmd_valid) begin
                    cmd_valid <= 1'b1;
                    cmd_kind <= 2'd2;
                    cmd_page <= active_v_page;
                    cmd_base_addr <= add_group_offset(v_base_addr, active_kv_tile);
                    cmd_bytes <= 16'd1024;
                    cmd_tag <= 8'h80 | {2'd0, active_kv_tile};
                    expect_tag_reg <= 8'h80 | {2'd0, active_kv_tile};
                    v_load_start <= 1'b1;
                    state_reg <= ST_V_WAIT;
                end
            end
            ST_V_WAIT: begin
                if (dma_done_valid && (dma_done_tag == expect_tag_reg)) begin
                    kv_ready_reg <= !dma_done_error;
                    state_reg <= ST_RUN;
                end
            end
            ST_RUN: begin
                if (prefetch_state_reg == PF_IDLE) begin
                    if ((active_kv_tile < active_q_group) && !cmd_valid) begin
                        prefetch_tile_reg <= active_kv_tile + 6'd1;
                        prefetch_page_reg <= ~active_k_page;
                        cmd_valid <= 1'b1;
                        cmd_kind <= 2'd1;
                        cmd_page <= ~active_k_page;
                        cmd_base_addr <= add_group_offset(k_base_addr, active_kv_tile + 6'd1);
                        cmd_bytes <= 16'd1024;
                        cmd_tag <= 8'h40 | {2'd0, active_kv_tile + 6'd1};
                        prefetch_expect_tag_reg <= 8'h40 | {2'd0, active_kv_tile + 6'd1};
                        k_load_start <= 1'b1;
                        prefetch_state_reg <= PF_K_WAIT;
                    end
                end else if (prefetch_state_reg == PF_K_WAIT) begin
                    if (dma_done_valid && (dma_done_tag == prefetch_expect_tag_reg))
                        prefetch_state_reg <= PF_K_READY;
                end else if (prefetch_state_reg == PF_K_READY) begin
                    if (!cmd_valid) begin
                        cmd_valid <= 1'b1;
                        cmd_kind <= 2'd2;
                        cmd_page <= prefetch_page_reg;
                        cmd_base_addr <= add_group_offset(v_base_addr, prefetch_tile_reg);
                        cmd_bytes <= 16'd1024;
                        cmd_tag <= 8'h80 | {2'd0, prefetch_tile_reg};
                        prefetch_expect_tag_reg <= 8'h80 | {2'd0, prefetch_tile_reg};
                        v_load_start <= 1'b1;
                        prefetch_state_reg <= PF_V_WAIT;
                    end
                end else if (prefetch_state_reg == PF_V_WAIT) begin
                    if (dma_done_valid && (dma_done_tag == prefetch_expect_tag_reg))
                        prefetch_state_reg <= PF_READY;
                end

                if (next_tile_pending_reg && (prefetch_state_reg == PF_READY) && !cmd_valid)
                    state_reg <= ST_NEXT_READY;

                if (scheduler_tile_done) begin
                    kv_ready_reg <= 1'b0;
                    if (active_kv_tile < active_q_group) begin
                        next_tile_pending_reg <= 1'b1;
                        if (prefetch_state_reg == PF_READY)
                            state_reg <= ST_NEXT_READY;
                    end
                end
                if (scheduler_group_done) begin
                    finalize_start <= 1'b1;
                    prefetch_state_reg <= PF_IDLE;
                    next_tile_pending_reg <= 1'b0;
                    state_reg <= ST_O_CMD;
                end
            end
            ST_NEXT_READY: begin
                active_kv_tile <= prefetch_tile_reg;
                active_k_page <= prefetch_page_reg;
                active_v_page <= prefetch_page_reg;
                kv_ready_reg <= 1'b1;
                prefetch_state_reg <= PF_IDLE;
                next_tile_pending_reg <= 1'b0;
                state_reg <= ST_RUN;
            end
            ST_NEXT_V_CMD: begin
                if (!cmd_valid) begin
                    cmd_valid <= 1'b1;
                    cmd_kind <= 2'd2;
                    cmd_page <= prefetch_page_reg;
                    cmd_base_addr <= add_group_offset(v_base_addr, prefetch_tile_reg);
                    cmd_bytes <= 16'd1024;
                    cmd_tag <= 8'h80 | {2'd0, prefetch_tile_reg};
                    expect_tag_reg <= 8'h80 | {2'd0, prefetch_tile_reg};
                    v_load_start <= 1'b1;
                    state_reg <= ST_NEXT_V_WAIT;
                end
            end
            ST_NEXT_V_WAIT: begin
                if (dma_done_valid && (dma_done_tag == expect_tag_reg)) begin
                    active_kv_tile <= prefetch_tile_reg;
                    active_k_page <= prefetch_page_reg;
                    active_v_page <= prefetch_page_reg;
                    kv_ready_reg <= !dma_done_error;
                    prefetch_state_reg <= PF_IDLE;
                    next_tile_pending_reg <= 1'b0;
                    state_reg <= ST_RUN;
                end
            end
            ST_O_CMD: begin
                if (!cmd_valid) begin
                    cmd_valid <= 1'b1;
                    cmd_kind <= 2'd3;
                    cmd_page <= active_q_page;
                    cmd_base_addr <= add_group_offset(o_base_addr, active_q_group);
                    cmd_bytes <= 16'd1024;
                    cmd_tag <= 8'hc0 | {2'd0, active_q_group};
                    expect_tag_reg <= 8'hc0 | {2'd0, active_q_group};
                    o_store_start <= 1'b1;
                    state_reg <= ST_O_WAIT;
                end
            end
            ST_O_WAIT: begin
                if (dma_done_valid && (dma_done_tag == expect_tag_reg)) begin
                    if (active_q_group == num_groups - 6'd1) begin
                        state_reg <= ST_DONE;
                    end else begin
                        active_q_group <= active_q_group + 6'd1;
                        active_kv_tile <= 6'd0;
                        active_q_page <= ~active_q_page;
                        active_k_page <= 1'b0;
                        active_v_page <= 1'b0;
                        q_ready_reg <= 1'b0;
                        kv_ready_reg <= 1'b0;
                        prefetch_state_reg <= PF_IDLE;
                        next_tile_pending_reg <= 1'b0;
                        state_reg <= ST_Q_CMD;
                    end
                end
            end
            ST_DONE: begin
                if (task_chain_enable && task_queue_not_empty) begin
                    task_dequeue <= 1'b1;
                    active_q_group <= 6'd0;
                    active_kv_tile <= 6'd0;
                    active_q_page <= 1'b0;
                    active_k_page <= 1'b0;
                    active_v_page <= 1'b0;
                    q_ready_reg <= 1'b0;
                    kv_ready_reg <= 1'b0;
                    prefetch_state_reg <= PF_IDLE;
                    next_tile_pending_reg <= 1'b0;
                    error <= 1'b0;
                    state_reg <= ST_Q_CMD;
                end else begin
                    done <= 1'b1;
                    state_reg <= ST_IDLE;
                end
            end
            default: state_reg <= ST_IDLE;
        endcase
    end
end

endmodule

`default_nettype wire
