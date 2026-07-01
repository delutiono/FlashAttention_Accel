`timescale 1ns/1ps
`default_nettype none

// baseline4 第一版计算核：dot -> score/exp -> 8-entry token FIFO -> update。
// 调度器提供 m_old 和 score tag；本模块拥有全部 Q/K/V/ACC/meta SRAM。
module packed_compute_core (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [7:0]          valid_len,
    input  wire                q_load_valid,
    input  wire [1:0]          q_load_pair,
    input  wire [4:0]          q_load_addr,
    input  wire [15:0]         q_load_wmask,
    input  wire [127:0]        q_load_data,
    input  wire                q_ext_valid,
    input  wire                q_ext_write,
    input  wire [1:0]          q_ext_pair,
    input  wire [4:0]          q_ext_addr,
    input  wire [15:0]         q_ext_wmask,
    input  wire [127:0]        q_ext_wdata,
    output wire                q_ext_rvalid,
    output wire [127:0]        q_ext_rdata,
    input  wire                k_load_valid,
    input  wire [1:0]          k_load_pair,
    input  wire [4:0]          k_load_addr,
    input  wire [15:0]         k_load_wmask,
    input  wire [127:0]        k_load_data,
    input  wire                v_load_valid,
    input  wire                v_load_pair,
    input  wire [5:0]          v_load_addr,
    input  wire [15:0]         v_load_wmask,
    input  wire [127:0]        v_load_data,
    input  wire                init_valid,
    output wire                init_ready,
    input  wire [2:0]          init_context,
    input  wire                score_valid,
    output wire                score_ready,
    input  wire                score_q_page,
    input  wire [2:0]          score_q_row,
    input  wire                score_k_page,
    input  wire [2:0]          score_k_row,
    input  wire                score_v_page,
    input  wire [2:0]          score_v_row,
    input  wire signed [31:0]  score_m_old,
    input  wire [15:0]         score_scale,
    input  wire [9:0]          score_user_token,
    input  wire [2:0]          score_context,
    input  wire                score_last,
    output wire                complete_valid,
    output wire [2:0]          complete_context,
    output wire [9:0]          complete_user_token,
    output wire                complete_last,
    output wire signed [31:0]  complete_m,
    output wire signed [47:0]  complete_l,
    output wire [3:0]          token_fifo_occupancy,
    input  wire                fin_acc_req_valid,
    output wire                fin_acc_req_ready,
    input  wire [2:0]          fin_acc_req_context,
    input  wire [1:0]          fin_acc_req_quarter,
    input  wire [2:0]          fin_acc_req_pair,
    output wire                fin_acc_rsp_valid,
    output wire signed [95:0]  fin_acc_rsp_data
);

localparam integer TOKEN_CTX_LSB = 0;
localparam integer TOKEN_V_ROW_LSB = 3;
localparam integer TOKEN_V_PAGE_BIT = 6;
localparam integer TOKEN_LAST_BIT = 7;
localparam integer TOKEN_USER_LSB = 8;

wire dot_ready;
wire dot_valid;
wire signed [47:0] dot_value;
wire [17:0] dot_token;
wire exp_valid;
wire signed [31:0] exp_score;
wire signed [31:0] exp_m_new;
wire [15:0] exp_alpha;
wire [15:0] exp_beta;
wire [17:0] exp_token;
wire fifo_ready;
wire fifo_valid;
wire signed [31:0] fifo_m_new;
wire [15:0] fifo_alpha;
wire [15:0] fifo_beta;
wire [17:0] fifo_token;
wire update_ready;
wire [17:0] update_complete_token;
reg [3:0] pipeline_reserved_reg;
reg signed [31:0] issue_m_mem [0:7];
reg [15:0] issue_scale_mem [0:7];
reg        pad_mask_mem [0:7];
reg [2:0] issue_meta_wr_ptr_reg;
reg [2:0] issue_meta_rd_ptr_reg;
reg [3:0] issue_meta_count_reg;
wire score_fire;
wire pad_mask_fire;
wire [4:0] reserved_total;

function [17:0] pack_score_token;
    input [9:0] user_token;
    input last;
    input v_page;
    input [2:0] v_row;
    input [2:0] ctx;
    reg [15:0] value;
    begin
        value = 18'd0;
        value[TOKEN_USER_LSB +: 10] = user_token;
        value[TOKEN_LAST_BIT] = last;
        value[TOKEN_V_PAGE_BIT] = v_page;
        value[TOKEN_V_ROW_LSB +: 3] = v_row;
        value[TOKEN_CTX_LSB +: 3] = ctx;
        pack_score_token = value;
    end
endfunction

assign reserved_total = {1'b0, pipeline_reserved_reg} + {1'b0, token_fifo_occupancy};
assign score_ready = dot_ready && (reserved_total < 5'd8) && (issue_meta_count_reg < 4'd8);
assign score_fire = score_valid && score_ready;
assign pad_mask_fire = (valid_len != 0) && (score_user_token >= valid_len);
assign complete_user_token = update_complete_token[TOKEN_USER_LSB +: 10];

always @(posedge clk) begin
    if (!rst_n) begin
        pipeline_reserved_reg <= 4'd0;
        issue_meta_wr_ptr_reg <= 3'd0;
        issue_meta_rd_ptr_reg <= 3'd0;
        issue_meta_count_reg <= 4'd0;
    end else begin
        case ({score_fire, exp_valid && fifo_ready})
            2'b10: pipeline_reserved_reg <= pipeline_reserved_reg + 4'd1;
            2'b01: pipeline_reserved_reg <= pipeline_reserved_reg - 4'd1;
            default: pipeline_reserved_reg <= pipeline_reserved_reg;
        endcase
        if (score_fire) begin
            issue_m_mem[issue_meta_wr_ptr_reg] <= score_m_old;
            issue_scale_mem[issue_meta_wr_ptr_reg] <= score_scale;
            pad_mask_mem[issue_meta_wr_ptr_reg] <= pad_mask_fire;
            issue_meta_wr_ptr_reg <= issue_meta_wr_ptr_reg + 3'd1;
        end
        if (dot_valid)
            issue_meta_rd_ptr_reg <= issue_meta_rd_ptr_reg + 3'd1;
        case ({score_fire, dot_valid})
            2'b10: issue_meta_count_reg <= issue_meta_count_reg + 4'd1;
            2'b01: issue_meta_count_reg <= issue_meta_count_reg - 4'd1;
            default: issue_meta_count_reg <= issue_meta_count_reg;
        endcase
`ifndef SYNTHESIS
        if (score_fire && (issue_meta_count_reg == 4'd8)) begin
            $display("ERROR: issue metadata FIFO overflow");
            $finish;
        end
        if (dot_valid && (issue_meta_count_reg == 4'd0)) begin
            $display("ERROR: issue metadata FIFO underflow");
            $finish;
        end
        if (exp_valid && !fifo_ready) begin
            $display("ERROR: update token FIFO credit violation");
            $finish;
        end
`endif
    end
end

dot_frontend #(.TOKEN_WIDTH(18)) u_dot (
    .clk(clk), .rst_n(rst_n),
    .q_load_valid(q_load_valid), .q_load_pair(q_load_pair), .q_load_addr(q_load_addr),
    .q_load_wmask(q_load_wmask), .q_load_data(q_load_data),
    .q_ext_valid(q_ext_valid), .q_ext_write(q_ext_write), .q_ext_pair(q_ext_pair),
    .q_ext_addr(q_ext_addr), .q_ext_wmask(q_ext_wmask), .q_ext_wdata(q_ext_wdata),
    .q_ext_rvalid(q_ext_rvalid), .q_ext_rdata(q_ext_rdata),
    .k_load_valid(k_load_valid), .k_load_pair(k_load_pair), .k_load_addr(k_load_addr),
    .k_load_wmask(k_load_wmask), .k_load_data(k_load_data),
    .in_valid(score_fire), .in_ready(dot_ready),
    .in_q_page(score_q_page), .in_q_row(score_q_row),
    .in_k_page(score_k_page), .in_k_row(score_k_row),
    .in_token(pack_score_token(score_user_token, score_last, score_v_page,
                               score_v_row, score_context)),
    .out_valid(dot_valid), .out_dot(dot_value), .out_token(dot_token)
);

score_exp_pipe #(.TOKEN_WIDTH(18)) u_score_exp (
    .clk(clk), .rst_n(rst_n), .in_valid(dot_valid), .in_ready(),
    .in_dot(dot_value), .in_scale(issue_scale_mem[issue_meta_rd_ptr_reg]),
    .in_m_old(issue_m_mem[issue_meta_rd_ptr_reg]),
    .in_token(dot_token), .out_valid(exp_valid), .out_score(exp_score),
	    .in_mask_valid(pad_mask_mem[issue_meta_rd_ptr_reg]),
    .out_m_new(exp_m_new), .out_alpha(exp_alpha), .out_beta(exp_beta),
    .out_token(exp_token)
);

update_token_fifo #(.DEPTH(8), .TOKEN_WIDTH(18)) u_fifo (
    .clk(clk), .rst_n(rst_n), .in_valid(exp_valid), .in_ready(fifo_ready),
    .in_m_new(exp_m_new), .in_alpha(exp_alpha), .in_beta(exp_beta), .in_token(exp_token),
    .out_valid(fifo_valid), .out_ready(update_ready), .out_m_new(fifo_m_new),
    .out_alpha(fifo_alpha), .out_beta(fifo_beta), .out_token(fifo_token),
    .occupancy(token_fifo_occupancy)
);

update_state_cluster #(.TOKEN_WIDTH(18)) u_update (
    .clk(clk), .rst_n(rst_n),
    .v_load_valid(v_load_valid), .v_load_pair(v_load_pair), .v_load_addr(v_load_addr),
    .v_load_wmask(v_load_wmask), .v_load_data(v_load_data),
    .init_valid(init_valid), .init_ready(init_ready), .init_context(init_context),
    .update_valid(fifo_valid), .update_ready(update_ready),
    .update_context(fifo_token[TOKEN_CTX_LSB +: 3]),
    .update_v_page(fifo_token[TOKEN_V_PAGE_BIT]),
    .update_v_row(fifo_token[TOKEN_V_ROW_LSB +: 3]), .update_m_new(fifo_m_new),
    .update_alpha(fifo_alpha), .update_beta(fifo_beta), .update_token(fifo_token),
    .update_last(fifo_token[TOKEN_LAST_BIT]), .complete_valid(complete_valid),
    .complete_context(complete_context), .complete_token(update_complete_token),
    .complete_last(complete_last), .complete_m(complete_m), .complete_l(complete_l),
    .fin_acc_req_valid(fin_acc_req_valid), .fin_acc_req_ready(fin_acc_req_ready),
    .fin_acc_req_context(fin_acc_req_context), .fin_acc_req_quarter(fin_acc_req_quarter),
    .fin_acc_req_pair(fin_acc_req_pair), .fin_acc_rsp_valid(fin_acc_rsp_valid),
    .fin_acc_rsp_data(fin_acc_rsp_data)
);

endmodule

`default_nettype wire
