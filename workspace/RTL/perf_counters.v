`timescale 1ns/1ps
`default_nettype none

module perf_counters (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        enable,
    input  wire        score_issue,
    input  wire        update_quarter,
    input  wire        update_complete,
    input  wire        dma_rd_busy,
    input  wire        dma_wr_busy,
    input  wire        finalize_busy,
    input  wire        stall_q_page,
    input  wire        stall_kv_page,
    input  wire        stall_fifo,
    input  wire [4:0]  read_index,
    output reg  [31:0] read_data
);

reg [63:0] total_cycles;
reg [63:0] score_count;
reg [63:0] update_quarter_count;
reg [63:0] update_complete_count;
reg [63:0] dma_rd_busy_count;
reg [63:0] dma_wr_busy_count;
reg [63:0] finalize_busy_count;
reg [63:0] stall_q_count;
reg [63:0] stall_kv_count;
reg [63:0] stall_fifo_count;

always @(posedge clk) begin
    if (!rst_n || clear) begin
        total_cycles <= 64'd0;
        score_count <= 64'd0;
        update_quarter_count <= 64'd0;
        update_complete_count <= 64'd0;
        dma_rd_busy_count <= 64'd0;
        dma_wr_busy_count <= 64'd0;
        finalize_busy_count <= 64'd0;
        stall_q_count <= 64'd0;
        stall_kv_count <= 64'd0;
        stall_fifo_count <= 64'd0;
    end else if (enable) begin
        total_cycles <= total_cycles + 64'd1;
        if (score_issue) score_count <= score_count + 64'd1;
        if (update_quarter) update_quarter_count <= update_quarter_count + 64'd1;
        if (update_complete) update_complete_count <= update_complete_count + 64'd1;
        if (dma_rd_busy) dma_rd_busy_count <= dma_rd_busy_count + 64'd1;
        if (dma_wr_busy) dma_wr_busy_count <= dma_wr_busy_count + 64'd1;
        if (finalize_busy) finalize_busy_count <= finalize_busy_count + 64'd1;
        if (stall_q_page) stall_q_count <= stall_q_count + 64'd1;
        if (stall_kv_page) stall_kv_count <= stall_kv_count + 64'd1;
        if (stall_fifo) stall_fifo_count <= stall_fifo_count + 64'd1;
    end
end

always @(*) begin
    case (read_index)
        5'd0: read_data = total_cycles[31:0];
        5'd1: read_data = total_cycles[63:32];
        5'd2: read_data = score_count[31:0];
        5'd3: read_data = score_count[63:32];
        5'd4: read_data = update_quarter_count[31:0];
        5'd5: read_data = update_complete_count[31:0];
        5'd6: read_data = dma_rd_busy_count[31:0];
        5'd7: read_data = dma_wr_busy_count[31:0];
        5'd8: read_data = finalize_busy_count[31:0];
        5'd9: read_data = stall_q_count[31:0];
        5'd10: read_data = stall_kv_count[31:0];
        5'd11: read_data = stall_fifo_count[31:0];
        default: read_data = 32'd0;
    endcase
end

endmodule

`default_nettype wire
