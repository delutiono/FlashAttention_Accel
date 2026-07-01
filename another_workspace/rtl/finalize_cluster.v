`timescale 1ns/1ps
`default_nettype none

// 将单行 ACC/l 归一化为 8 个 128-bit O beat。
// ACC 采用窄流式读接口：每次返回 2 个 signed 48-bit lane，避免跨模块 768-bit 宽口。
module finalize_cluster (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [1:0]           format_sel,
    input  wire                 req_valid,
    output wire                 req_ready,
    input  wire [2:0]           req_context,
    input  wire                 req_q_page,
    input  wire [2:0]           req_q_row,
    input  wire signed [47:0]   req_l,

    output reg                  acc_req_valid,
    input  wire                 acc_req_ready,
    output reg [2:0]            acc_req_context,
    output reg [1:0]            acc_req_quarter,
    output reg [2:0]            acc_req_pair,
    input  wire                 acc_rsp_valid,
    input  wire signed [95:0]   acc_rsp_data,

    output reg                  o_valid,
    input  wire                 o_ready,
    output reg                  o_page,
    output reg [2:0]            o_row,
    output reg                  o_half,
    output reg [1:0]            o_pair,
    output reg [127:0]          o_data,
    output reg                  o_last,

    output reg                  done_valid,
    output reg [2:0]            done_context,
    output reg [2:0]            done_row,
    output reg                  error_zero_l
);

localparam [1:0] ST_IDLE  = 2'd0;
localparam [1:0] ST_READ  = 2'd1;
localparam [1:0] ST_DONE  = 2'd2;

reg [1:0] state_reg;
reg [2:0] ctx_reg;
reg page_reg;
reg [2:0] row_reg;
reg [4:0] lane_pair_reg;
reg [4:0] rsp_pair_reg;
reg [2:0] pack_slot_reg;
reg [2:0] beat_idx_reg;
reg [127:0] pack_reg;

reg [2:0] req_ctx_mem [0:7];
reg       req_page_mem [0:7];
reg [2:0] req_row_mem [0:7];
reg signed [47:0] req_l_mem [0:7];
reg [2:0] req_wr_ptr_reg;
reg [2:0] req_rd_ptr_reg;
reg [3:0] req_count_reg;

wire inv_in_ready;
reg inv_in_valid_reg;
reg signed [47:0] inv_in_l_reg;
reg [2:0] inv_in_token_reg;
wire inv_out_valid;
wire [31:0] inv_out;
wire [2:0] inv_token;
wire inv_zero_l;
reg [31:0] inv_reg;
reg inv_busy_reg;
reg inv_meta_page_reg;
reg [2:0] inv_meta_row_reg;

reg [2:0] inv_ctx_mem [0:7];
reg       inv_page_mem [0:7];
reg [2:0] inv_row_mem [0:7];
reg [31:0] inv_value_mem [0:7];
reg       inv_zero_mem [0:7];
reg [2:0] inv_wr_ptr_reg;
reg [2:0] inv_rd_ptr_reg;
reg [3:0] inv_count_reg;

wire norm_in_ready;
reg norm_in_valid_reg;
wire norm_out_valid;
wire norm_out_ready;
wire [31:0] norm_out_data;
wire [4:0] norm_out_token;
reg [95:0] norm_acc_reg;
reg [4:0] norm_token_reg;
wire [4:0] next_lane_pair = lane_pair_reg + 5'd1;
wire req_fire = req_valid && req_ready;
wire recip_start = !inv_busy_reg && (req_count_reg != 4'd0) &&
                   (inv_count_reg != 4'd8) && inv_in_ready;
wire recip_done = inv_out_valid;
wire proc_start = (state_reg == ST_IDLE) && (inv_count_reg != 4'd0) && (!o_valid || o_ready);

wire [5:0] output_shift;
assign output_shift = (format_sel == 2'd1) ? 6'd50 :
                      (format_sel == 2'd2) ? 6'd48 : 6'd52;

assign req_ready = (req_count_reg != 4'd8);

reciprocal_approx #(.TOKEN_WIDTH(3)) u_recip (
    .clk(clk), .rst_n(rst_n),
    .in_valid(inv_in_valid_reg), .in_ready(inv_in_ready),
    .in_l(inv_in_l_reg), .in_token(inv_in_token_reg),
    .out_valid(inv_out_valid), .out_ready(1'b1),
    .out_inv(inv_out), .out_token(inv_token), .error_zero_l(inv_zero_l)
);

output_norm_pipe #(.TOKEN_WIDTH(5), .LANES(2)) u_norm (
    .clk(clk), .rst_n(rst_n),
    .in_valid(norm_in_valid_reg), .in_ready(norm_in_ready),
    .in_acc(norm_acc_reg), .in_inv(inv_reg), .in_token(norm_token_reg),
    .out_valid(norm_out_valid), .out_ready(norm_out_ready),
    .out_data(norm_out_data), .out_token(norm_out_token),
    .output_shift(output_shift)
);

assign norm_out_ready = (pack_slot_reg != 3'd3) || (!o_valid) || o_ready;

always @(posedge clk) begin
    if (!rst_n) begin
        state_reg <= ST_IDLE;
        ctx_reg <= 3'd0;
        page_reg <= 1'b0;
        row_reg <= 3'd0;
        lane_pair_reg <= 5'd0;
        rsp_pair_reg <= 5'd0;
        pack_slot_reg <= 3'd0;
        beat_idx_reg <= 3'd0;
        pack_reg <= 128'd0;
        req_wr_ptr_reg <= 3'd0;
        req_rd_ptr_reg <= 3'd0;
        req_count_reg <= 4'd0;
        inv_in_valid_reg <= 1'b0;
        inv_in_l_reg <= 48'sd0;
        inv_in_token_reg <= 3'd0;
        inv_reg <= 32'd0;
        inv_busy_reg <= 1'b0;
        inv_meta_page_reg <= 1'b0;
        inv_meta_row_reg <= 3'd0;
        inv_wr_ptr_reg <= 3'd0;
        inv_rd_ptr_reg <= 3'd0;
        inv_count_reg <= 4'd0;
        norm_in_valid_reg <= 1'b0;
        norm_acc_reg <= 96'd0;
        norm_token_reg <= 5'd0;
        acc_req_valid <= 1'b0;
        acc_req_context <= 3'd0;
        acc_req_quarter <= 2'd0;
        acc_req_pair <= 3'd0;
        o_valid <= 1'b0;
        o_page <= 1'b0;
        o_row <= 3'd0;
        o_half <= 1'b0;
        o_pair <= 2'd0;
        o_data <= 128'd0;
        o_last <= 1'b0;
        done_valid <= 1'b0;
        done_context <= 3'd0;
        done_row <= 3'd0;
        error_zero_l <= 1'b0;
    end else begin
        done_valid <= 1'b0;
        inv_in_valid_reg <= 1'b0;
        norm_in_valid_reg <= 1'b0;
        if (o_valid && o_ready)
            o_valid <= 1'b0;

        if (req_fire) begin
            req_ctx_mem[req_wr_ptr_reg] <= req_context;
            req_page_mem[req_wr_ptr_reg] <= req_q_page;
            req_row_mem[req_wr_ptr_reg] <= req_q_row;
            req_l_mem[req_wr_ptr_reg] <= req_l;
            req_wr_ptr_reg <= req_wr_ptr_reg + 3'd1;
        end

        if (recip_start) begin
            inv_in_valid_reg <= 1'b1;
            inv_in_l_reg <= req_l_mem[req_rd_ptr_reg];
            inv_in_token_reg <= req_ctx_mem[req_rd_ptr_reg];
            inv_meta_page_reg <= req_page_mem[req_rd_ptr_reg];
            inv_meta_row_reg <= req_row_mem[req_rd_ptr_reg];
            req_rd_ptr_reg <= req_rd_ptr_reg + 3'd1;
            inv_busy_reg <= 1'b1;
        end

        case ({req_fire, recip_start})
            2'b10: req_count_reg <= req_count_reg + 4'd1;
            2'b01: req_count_reg <= req_count_reg - 4'd1;
            default: req_count_reg <= req_count_reg;
        endcase

        if (recip_done) begin
            inv_ctx_mem[inv_wr_ptr_reg] <= inv_token;
            inv_page_mem[inv_wr_ptr_reg] <= inv_meta_page_reg;
            inv_row_mem[inv_wr_ptr_reg] <= inv_meta_row_reg;
            inv_value_mem[inv_wr_ptr_reg] <= inv_out;
            inv_zero_mem[inv_wr_ptr_reg] <= inv_zero_l;
            inv_wr_ptr_reg <= inv_wr_ptr_reg + 3'd1;
            inv_busy_reg <= 1'b0;
        end

        case (state_reg)
            ST_IDLE: begin
                acc_req_valid <= 1'b0;
                if (proc_start) begin
                    ctx_reg <= inv_ctx_mem[inv_rd_ptr_reg];
                    page_reg <= inv_page_mem[inv_rd_ptr_reg];
                    row_reg <= inv_row_mem[inv_rd_ptr_reg];
                    inv_reg <= inv_value_mem[inv_rd_ptr_reg];
                    error_zero_l <= inv_zero_mem[inv_rd_ptr_reg];
                    inv_rd_ptr_reg <= inv_rd_ptr_reg + 3'd1;
                    inv_count_reg <= inv_count_reg - 4'd1;
                    lane_pair_reg <= 5'd0;
                    rsp_pair_reg <= 5'd0;
                    pack_slot_reg <= 3'd0;
                    beat_idx_reg <= 3'd0;
                    pack_reg <= 128'd0;
                    acc_req_valid <= 1'b1;
                    acc_req_context <= inv_ctx_mem[inv_rd_ptr_reg];
                    acc_req_quarter <= 2'd0;
                    acc_req_pair <= 3'd0;
                    state_reg <= ST_READ;
                end
            end
            ST_READ: begin
                if (acc_req_valid && acc_req_ready) begin
                    if (lane_pair_reg == 5'd31) begin
                        acc_req_valid <= 1'b0;
                    end else begin
                        lane_pair_reg <= next_lane_pair;
                        acc_req_context <= ctx_reg;
                        acc_req_quarter <= next_lane_pair[4:3];
                        acc_req_pair <= next_lane_pair[2:0];
                    end
                end
                if (acc_rsp_valid && norm_in_ready) begin
                    norm_acc_reg <= acc_rsp_data;
                    norm_token_reg <= rsp_pair_reg;
                    norm_in_valid_reg <= 1'b1;
                    rsp_pair_reg <= rsp_pair_reg + 5'd1;
                end
                if (norm_out_valid && norm_out_ready) begin
                    case (pack_slot_reg)
                        3'd0: pack_reg[31:0] <= norm_out_data;
                        3'd1: pack_reg[63:32] <= norm_out_data;
                        3'd2: pack_reg[95:64] <= norm_out_data;
                        default: begin
                            if (!o_valid || o_ready) begin
                                o_valid <= 1'b1;
                                o_page <= page_reg;
                                o_row <= row_reg;
                                o_half <= beat_idx_reg[2];
                                o_pair <= beat_idx_reg[1:0];
                                o_data <= {norm_out_data, pack_reg[95:0]};
                                o_last <= (beat_idx_reg == 3'd7);
                                beat_idx_reg <= beat_idx_reg + 3'd1;
                                pack_reg <= 128'd0;
                            end
                        end
                    endcase
                    pack_slot_reg <= (pack_slot_reg == 3'd3) ? 3'd0 : (pack_slot_reg + 3'd1);
                    if ((norm_out_token == 5'd31) && (pack_slot_reg == 3'd3))
                        state_reg <= ST_DONE;
                end
`ifndef SYNTHESIS
                if (acc_rsp_valid && !norm_in_ready) begin
                    $display("ERROR: finalize normalize pipe backpressure would drop ACC response");
                    $finish;
                end
`endif
            end
            ST_DONE: begin
                if (!o_valid || o_ready) begin
                    done_valid <= 1'b1;
                    done_context <= ctx_reg;
                    done_row <= row_reg;
                    state_reg <= ST_IDLE;
                end
            end
            default: state_reg <= ST_IDLE;
        endcase

        if (recip_done && !proc_start) begin
            inv_count_reg <= inv_count_reg + 4'd1;
        end else if (recip_done && proc_start) begin
            inv_count_reg <= inv_count_reg;
        end
    end
end

endmodule

`default_nettype wire
