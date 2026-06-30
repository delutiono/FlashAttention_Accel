`timescale 1ns/1ps
`default_nettype none

// 32-lane, two-half online-softmax update cluster.
// ACC/l use signed Q*.30, V uses signed Q8.8, alpha/beta use unsigned Q1.15.
module update_state_cluster #(
    parameter TOKEN_WIDTH = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    v_load_valid,
    input  wire                    v_load_pair,
    input  wire [5:0]              v_load_addr,
    input  wire [15:0]             v_load_wmask,
    input  wire [127:0]            v_load_data,

    input  wire                    init_valid,
    output wire                    init_ready,
    input  wire [2:0]              init_context,

    input  wire                    update_valid,
    output wire                    update_ready,
    input  wire [2:0]              update_context,
    input  wire                    update_v_page,
    input  wire [2:0]              update_v_row,
    input  wire signed [31:0]      update_m_new,
    input  wire [15:0]             update_alpha,
    input  wire [15:0]             update_beta,
    input  wire [TOKEN_WIDTH-1:0]  update_token,
    input  wire                    update_last,

    output reg                     complete_valid,
    output reg [2:0]               complete_context,
    output reg [TOKEN_WIDTH-1:0]   complete_token,
    output reg                     complete_last,
    output reg signed [31:0]       complete_m,
    output reg signed [47:0]       complete_l,

    input  wire                    fin_acc_req_valid,
    output wire                    fin_acc_req_ready,
    input  wire [2:0]              fin_acc_req_context,
    input  wire [1:0]              fin_acc_req_quarter,
    input  wire [2:0]              fin_acc_req_pair,
    output reg                     fin_acc_rsp_valid,
    output reg signed [95:0]       fin_acc_rsp_data
);

localparam integer LANES = 32;
localparam integer ACC_WIDTH = 48;
localparam integer ACC_PRODUCT_WIDTH = 65;
localparam integer V_PRODUCT_WIDTH = 33;
localparam integer SUM_WIDTH = 66;

reg                    init_active_reg;
reg                    init_half_reg;
reg [2:0]              init_context_reg;

reg                    issue_active_reg;
reg                    issue_half_reg;
reg [2:0]              issue_context_reg;
reg                    issue_v_page_reg;
reg [2:0]              issue_v_row_reg;
reg signed [31:0]      issue_m_new_reg;
reg [15:0]             issue_alpha_reg;
reg [15:0]             issue_beta_reg;
reg [TOKEN_WIDTH-1:0]  issue_token_reg;
reg                    issue_last_reg;

wire                   update_fire;
wire                   half_issue;
wire [3:0]             acc_rd_addr;
wire                   acc_rd_en;
wire                   acc_rd_valid;
wire [127:0]           acc_rd_bank [0:11];
wire [1535:0]          acc_rd_packed;
wire [1535:0]          acc_wr_packed;
wire [127:0]           acc_wr_bank [0:11];
wire                   acc_wr_en;
wire [3:0]             acc_wr_addr;

wire [5:0]             v_rd_addr;
wire                   v_rd_valid;
wire [63:0]            v_rd_bank [0:7];
wire [511:0]           v_rd_packed;

reg [1:0]              rd_valid_pipe;
reg                    rd_half_pipe [0:1];
reg [2:0]              rd_context_pipe [0:1];
reg [15:0]             rd_alpha_pipe [0:1];
reg [15:0]             rd_beta_pipe [0:1];
reg [TOKEN_WIDTH-1:0]  rd_token_pipe [0:1];
reg                    rd_last_pipe [0:1];

reg                    mul_valid_reg;
reg                    mul_half_reg;
reg [2:0]              mul_context_reg;
reg [TOKEN_WIDTH-1:0]  mul_token_reg;
reg                    mul_last_reg;
reg signed [ACC_PRODUCT_WIDTH-1:0] acc_mul_reg [0:LANES-1];
reg signed [V_PRODUCT_WIDTH-1:0]   v_mul_reg [0:LANES-1];

reg                    sum_valid_reg;
reg                    sum_half_reg;
reg [2:0]              sum_context_reg;
reg [TOKEN_WIDTH-1:0]  sum_token_reg;
reg                    sum_last_reg;
reg signed [ACC_WIDTH-1:0] acc_next_reg [0:LANES-1];

wire                   meta_read_issue;
wire                   meta_rd_valid;
wire [127:0]           meta_rd_data;
reg [1:0]              meta_tag_valid_pipe;
reg [2:0]              meta_context_pipe [0:1];
reg signed [31:0]      meta_m_new_pipe [0:1];
reg [15:0]             meta_alpha_pipe [0:1];
reg [15:0]             meta_beta_pipe [0:1];

reg                    l_mul_valid_reg;
reg [2:0]              l_mul_context_reg;
reg signed [31:0]      l_mul_m_new_reg;
reg [15:0]             l_mul_beta_reg;
reg signed [64:0]      l_product_reg;
reg signed [47:0]      pending_l [0:7];
reg signed [31:0]      pending_m [0:7];
reg [7:0]              pending_meta_valid_reg;

reg                    meta_wr_en;
reg [3:0]              meta_wr_addr;
reg [127:0]            meta_wr_data;

wire [3:0]             fin_acc_addr;
wire                   fin_acc_fire;
reg [1:0]              fin_req_pipe_valid;
reg [3:0]              fin_pair_index_pipe [0:1];

integer i;

assign init_ready = !init_active_reg && !issue_active_reg;
// The next score may be accepted in the same cycle that the current half1 is
// issued. Old payload registers still drive half1 until the active clock edge.
assign update_ready = !init_active_reg &&
                      (!issue_active_reg || (issue_active_reg && issue_half_reg));
assign update_fire = update_valid && update_ready;
assign half_issue = issue_active_reg;

assign fin_acc_addr = {fin_acc_req_context, fin_acc_req_quarter[1]};
assign fin_acc_fire = fin_acc_req_valid && fin_acc_req_ready;
assign fin_acc_req_ready = !init_active_reg && !issue_active_reg;

assign acc_rd_addr = half_issue ? {issue_context_reg, issue_half_reg} : fin_acc_addr;
assign acc_rd_en = half_issue || fin_acc_fire;
assign v_rd_addr = {issue_v_page_reg, issue_v_row_reg, issue_half_reg, 1'b0};
assign meta_read_issue = half_issue && !issue_half_reg;

assign acc_wr_en = init_active_reg || sum_valid_reg;
assign acc_wr_addr = init_active_reg ? {init_context_reg, init_half_reg} :
                                      {sum_context_reg, sum_half_reg};

generate
    genvar pack_idx;
    for (pack_idx = 0; pack_idx < 12; pack_idx = pack_idx + 1) begin : g_acc_pack
        assign acc_rd_packed[pack_idx*128 +: 128] = acc_rd_bank[pack_idx];
        assign acc_wr_bank[pack_idx] = init_active_reg ? 128'd0 :
                                      acc_wr_packed[pack_idx*128 +: 128];
    end
    for (pack_idx = 0; pack_idx < 8; pack_idx = pack_idx + 1) begin : g_v_pack
        assign v_rd_packed[pack_idx*64 +: 64] = v_rd_bank[pack_idx];
    end
    for (pack_idx = 0; pack_idx < LANES; pack_idx = pack_idx + 1) begin : g_result_pack
        assign acc_wr_packed[pack_idx*ACC_WIDTH +: ACC_WIDTH] = acc_next_reg[pack_idx];
    end
endgenerate

function signed [ACC_WIDTH-1:0] sat_acc;
    input signed [SUM_WIDTH-1:0] value;
    reg signed [SUM_WIDTH-1:0] max_value;
    reg signed [SUM_WIDTH-1:0] min_value;
    begin
        max_value = {{(SUM_WIDTH-ACC_WIDTH){1'b0}}, 1'b0, {(ACC_WIDTH-1){1'b1}}};
        min_value = {{(SUM_WIDTH-ACC_WIDTH){1'b1}}, 1'b1, {(ACC_WIDTH-1){1'b0}}};
        if (value > max_value)
            sat_acc = {1'b0, {(ACC_WIDTH-1){1'b1}}};
        else if (value < min_value)
            sat_acc = {1'b1, {(ACC_WIDTH-1){1'b0}}};
        else
            sat_acc = value[ACC_WIDTH-1:0];
    end
endfunction

function signed [65:0] round_shift15;
    input signed [64:0] value;
    reg signed [65:0] magnitude;
    begin
        if (value >= 0)
            round_shift15 = (value + 65'sd16384) >>> 15;
        else begin
            magnitude = -$signed({value[64], value});
            round_shift15 = -((magnitude + 66'sd16384) >>> 15);
        end
    end
endfunction

v_sram_cluster u_v_sram (
    .clk(clk), .rst_n(rst_n),
    .rw_valid(v_load_valid), .rw_write(1'b1), .rw_pair(v_load_pair),
    .rw_addr(v_load_addr), .rw_wmask(v_load_wmask), .rw_wdata(v_load_data),
    .rw_rvalid(), .rw_rdata(),
    .wide_rd_en(half_issue), .wide_rd_addr(v_rd_addr), .wide_rd_valid(v_rd_valid),
    .wide_rd_data0(v_rd_bank[0]), .wide_rd_data1(v_rd_bank[1]),
    .wide_rd_data2(v_rd_bank[2]), .wide_rd_data3(v_rd_bank[3]),
    .wide_rd_data4(v_rd_bank[4]), .wide_rd_data5(v_rd_bank[5]),
    .wide_rd_data6(v_rd_bank[6]), .wide_rd_data7(v_rd_bank[7])
);

acc_sram_cluster u_acc_sram (
    .clk(clk), .rst_n(rst_n), .wr_en(acc_wr_en), .wr_addr(acc_wr_addr),
    .wr_data0(acc_wr_bank[0]), .wr_data1(acc_wr_bank[1]),
    .wr_data2(acc_wr_bank[2]), .wr_data3(acc_wr_bank[3]),
    .wr_data4(acc_wr_bank[4]), .wr_data5(acc_wr_bank[5]),
    .wr_data6(acc_wr_bank[6]), .wr_data7(acc_wr_bank[7]),
    .wr_data8(acc_wr_bank[8]), .wr_data9(acc_wr_bank[9]),
    .wr_data10(acc_wr_bank[10]), .wr_data11(acc_wr_bank[11]),
    .rd_en(acc_rd_en), .rd_addr(acc_rd_addr), .rd_valid(acc_rd_valid),
    .rd_data0(acc_rd_bank[0]), .rd_data1(acc_rd_bank[1]),
    .rd_data2(acc_rd_bank[2]), .rd_data3(acc_rd_bank[3]),
    .rd_data4(acc_rd_bank[4]), .rd_data5(acc_rd_bank[5]),
    .rd_data6(acc_rd_bank[6]), .rd_data7(acc_rd_bank[7]),
    .rd_data8(acc_rd_bank[8]), .rd_data9(acc_rd_bank[9]),
    .rd_data10(acc_rd_bank[10]), .rd_data11(acc_rd_bank[11])
);

meta_sram_cluster u_meta_sram (
    .clk(clk), .rst_n(rst_n), .wr_en(meta_wr_en), .wr_addr(meta_wr_addr),
    .wr_data(meta_wr_data), .rd_en(meta_read_issue),
    .rd_addr({1'b0, issue_context_reg}),
    .rd_valid(meta_rd_valid), .rd_data(meta_rd_data)
);

always @(posedge clk) begin
    if (!rst_n) begin
        init_active_reg <= 1'b0;
        init_half_reg <= 1'b0;
        init_context_reg <= 3'd0;
        issue_active_reg <= 1'b0;
        issue_half_reg <= 1'b0;
        issue_context_reg <= 3'd0;
        issue_v_page_reg <= 1'b0;
        issue_v_row_reg <= 3'd0;
        issue_m_new_reg <= 32'sd0;
        issue_alpha_reg <= 16'd0;
        issue_beta_reg <= 16'd0;
        issue_token_reg <= {TOKEN_WIDTH{1'b0}};
        issue_last_reg <= 1'b0;
        rd_valid_pipe <= 2'b00;
        rd_half_pipe[0] <= 1'b0;
        rd_half_pipe[1] <= 1'b0;
        rd_context_pipe[0] <= 3'd0;
        rd_context_pipe[1] <= 3'd0;
        rd_alpha_pipe[0] <= 16'd0;
        rd_alpha_pipe[1] <= 16'd0;
        rd_beta_pipe[0] <= 16'd0;
        rd_beta_pipe[1] <= 16'd0;
        rd_token_pipe[0] <= {TOKEN_WIDTH{1'b0}};
        rd_token_pipe[1] <= {TOKEN_WIDTH{1'b0}};
        rd_last_pipe[0] <= 1'b0;
        rd_last_pipe[1] <= 1'b0;
        mul_valid_reg <= 1'b0;
        mul_half_reg <= 1'b0;
        mul_context_reg <= 3'd0;
        mul_token_reg <= {TOKEN_WIDTH{1'b0}};
        mul_last_reg <= 1'b0;
        sum_valid_reg <= 1'b0;
        sum_half_reg <= 1'b0;
        sum_context_reg <= 3'd0;
        sum_token_reg <= {TOKEN_WIDTH{1'b0}};
        sum_last_reg <= 1'b0;
        meta_tag_valid_pipe <= 2'b00;
        meta_context_pipe[0] <= 3'd0;
        meta_context_pipe[1] <= 3'd0;
        meta_m_new_pipe[0] <= 32'sd0;
        meta_m_new_pipe[1] <= 32'sd0;
        meta_alpha_pipe[0] <= 16'd0;
        meta_alpha_pipe[1] <= 16'd0;
        meta_beta_pipe[0] <= 16'd0;
        meta_beta_pipe[1] <= 16'd0;
        l_mul_valid_reg <= 1'b0;
        l_mul_context_reg <= 3'd0;
        l_mul_m_new_reg <= 32'sd0;
        l_mul_beta_reg <= 16'd0;
        l_product_reg <= 65'sd0;
        pending_meta_valid_reg <= 8'd0;
        meta_wr_en <= 1'b0;
        meta_wr_addr <= 4'd0;
        meta_wr_data <= 128'd0;
        complete_valid <= 1'b0;
        complete_context <= 3'd0;
        complete_token <= {TOKEN_WIDTH{1'b0}};
        complete_last <= 1'b0;
        complete_m <= -32'sh80000000;
        complete_l <= 48'sd0;
        fin_acc_rsp_valid <= 1'b0;
        fin_acc_rsp_data <= 96'sd0;
        fin_req_pipe_valid <= 2'b00;
        fin_pair_index_pipe[0] <= 4'd0;
        fin_pair_index_pipe[1] <= 4'd0;
        for (i = 0; i < LANES; i = i + 1) begin
            acc_mul_reg[i] <= {ACC_PRODUCT_WIDTH{1'b0}};
            v_mul_reg[i] <= {V_PRODUCT_WIDTH{1'b0}};
            acc_next_reg[i] <= {ACC_WIDTH{1'b0}};
        end
        for (i = 0; i < 8; i = i + 1) begin
            pending_l[i] <= 48'sd0;
            pending_m[i] <= -32'sh80000000;
        end
    end else begin
        complete_valid <= 1'b0;
        meta_wr_en <= 1'b0;
        fin_acc_rsp_valid <= 1'b0;

        if (init_valid && init_ready) begin
            init_active_reg <= 1'b1;
            init_half_reg <= 1'b0;
            init_context_reg <= init_context;
            pending_l[init_context] <= 48'sd0;
            pending_m[init_context] <= -32'sh80000000;
            pending_meta_valid_reg[init_context] <= 1'b0;
            meta_wr_en <= 1'b1;
            meta_wr_addr <= {1'b0, init_context};
            meta_wr_data <= {48'd0, 48'd0, 32'h80000000};
        end else if (init_active_reg) begin
            if (init_half_reg)
                init_active_reg <= 1'b0;
            else
                init_half_reg <= 1'b1;
        end

        if (update_fire) begin
            issue_active_reg <= 1'b1;
            issue_half_reg <= 1'b0;
            issue_context_reg <= update_context;
            issue_v_page_reg <= update_v_page;
            issue_v_row_reg <= update_v_row;
            issue_m_new_reg <= update_m_new;
            issue_alpha_reg <= update_alpha;
            issue_beta_reg <= update_beta;
            issue_token_reg <= update_token;
            issue_last_reg <= update_last;
            pending_meta_valid_reg[update_context] <= 1'b0;
        end else if (issue_active_reg) begin
            if (issue_half_reg)
                issue_active_reg <= 1'b0;
            else
                issue_half_reg <= 1'b1;
        end

        rd_valid_pipe[0] <= half_issue;
        rd_valid_pipe[1] <= rd_valid_pipe[0];
        rd_half_pipe[0] <= issue_half_reg;
        rd_half_pipe[1] <= rd_half_pipe[0];
        rd_context_pipe[0] <= issue_context_reg;
        rd_context_pipe[1] <= rd_context_pipe[0];
        rd_alpha_pipe[0] <= issue_alpha_reg;
        rd_alpha_pipe[1] <= rd_alpha_pipe[0];
        rd_beta_pipe[0] <= issue_beta_reg;
        rd_beta_pipe[1] <= rd_beta_pipe[0];
        rd_token_pipe[0] <= issue_token_reg;
        rd_token_pipe[1] <= rd_token_pipe[0];
        rd_last_pipe[0] <= issue_last_reg;
        rd_last_pipe[1] <= rd_last_pipe[0];

        meta_tag_valid_pipe[0] <= meta_read_issue;
        meta_tag_valid_pipe[1] <= meta_tag_valid_pipe[0];
        meta_context_pipe[0] <= issue_context_reg;
        meta_context_pipe[1] <= meta_context_pipe[0];
        meta_m_new_pipe[0] <= issue_m_new_reg;
        meta_m_new_pipe[1] <= meta_m_new_pipe[0];
        meta_alpha_pipe[0] <= issue_alpha_reg;
        meta_alpha_pipe[1] <= meta_alpha_pipe[0];
        meta_beta_pipe[0] <= issue_beta_reg;
        meta_beta_pipe[1] <= meta_beta_pipe[0];

        // L1: multiplier-only stage. This removes multiply+round+add+saturate
        // from the critical path reported by Genus.
        l_mul_valid_reg <= meta_tag_valid_pipe[1] && meta_rd_valid;
        if (meta_tag_valid_pipe[1] && meta_rd_valid) begin
            l_mul_context_reg <= meta_context_pipe[1];
            l_mul_m_new_reg <= meta_m_new_pipe[1];
            l_mul_beta_reg <= meta_beta_pipe[1];
            l_product_reg <= $signed(meta_rd_data[79:32]) *
                             $signed({1'b0, meta_alpha_pipe[1]});
        end

        // L2: rounding, beta alignment, addition and saturation.
        if (l_mul_valid_reg) begin
            pending_m[l_mul_context_reg] <= l_mul_m_new_reg;
            pending_l[l_mul_context_reg] <= sat_acc(
                round_shift15(l_product_reg) +
                ($signed({1'b0, l_mul_beta_reg}) <<< 15));
            pending_meta_valid_reg[l_mul_context_reg] <= 1'b1;
        end

        mul_valid_reg <= rd_valid_pipe[1] && acc_rd_valid && v_rd_valid;
        mul_half_reg <= rd_half_pipe[1];
        mul_context_reg <= rd_context_pipe[1];
        mul_token_reg <= rd_token_pipe[1];
        mul_last_reg <= rd_last_pipe[1];
        if (rd_valid_pipe[1] && acc_rd_valid && v_rd_valid) begin
            for (i = 0; i < LANES; i = i + 1) begin
                acc_mul_reg[i] <= $signed(acc_rd_packed[i*ACC_WIDTH +: ACC_WIDTH]) *
                                  $signed({1'b0, rd_alpha_pipe[1]});
                v_mul_reg[i] <= $signed(v_rd_packed[i*16 +: 16]) *
                                $signed({1'b0, rd_beta_pipe[1]});
            end
        end

        sum_valid_reg <= mul_valid_reg;
        sum_half_reg <= mul_half_reg;
        sum_context_reg <= mul_context_reg;
        sum_token_reg <= mul_token_reg;
        sum_last_reg <= mul_last_reg;
        if (mul_valid_reg) begin
            for (i = 0; i < LANES; i = i + 1) begin
                acc_next_reg[i] <= sat_acc(
                    round_shift15(acc_mul_reg[i]) +
                    ($signed(v_mul_reg[i]) <<< 7));
            end
        end

        // ACC half1 write, meta write and completion commit together.
        if (sum_valid_reg && sum_half_reg) begin
            meta_wr_en <= 1'b1;
            meta_wr_addr <= {1'b0, sum_context_reg};
            meta_wr_data <= {48'd0, pending_l[sum_context_reg], pending_m[sum_context_reg]};
            complete_valid <= 1'b1;
            complete_context <= sum_context_reg;
            complete_token <= sum_token_reg;
            complete_last <= sum_last_reg;
            complete_m <= pending_m[sum_context_reg];
            complete_l <= pending_l[sum_context_reg];
            pending_meta_valid_reg[sum_context_reg] <= 1'b0;
`ifndef SYNTHESIS
            if (!pending_meta_valid_reg[sum_context_reg]) begin
                $display("ERROR: update completion before meta recurrence is ready");
                $finish;
            end
`endif
        end

        fin_req_pipe_valid[0] <= fin_acc_fire;
        fin_req_pipe_valid[1] <= fin_req_pipe_valid[0];
        fin_pair_index_pipe[0] <= {fin_acc_req_quarter[0], fin_acc_req_pair};
        fin_pair_index_pipe[1] <= fin_pair_index_pipe[0];
        if (fin_req_pipe_valid[1] && acc_rd_valid) begin
            fin_acc_rsp_valid <= 1'b1;
            case (fin_pair_index_pipe[1])
                4'd0:  fin_acc_rsp_data <= acc_rd_packed[0*96 +: 96];
                4'd1:  fin_acc_rsp_data <= acc_rd_packed[1*96 +: 96];
                4'd2:  fin_acc_rsp_data <= acc_rd_packed[2*96 +: 96];
                4'd3:  fin_acc_rsp_data <= acc_rd_packed[3*96 +: 96];
                4'd4:  fin_acc_rsp_data <= acc_rd_packed[4*96 +: 96];
                4'd5:  fin_acc_rsp_data <= acc_rd_packed[5*96 +: 96];
                4'd6:  fin_acc_rsp_data <= acc_rd_packed[6*96 +: 96];
                4'd7:  fin_acc_rsp_data <= acc_rd_packed[7*96 +: 96];
                4'd8:  fin_acc_rsp_data <= acc_rd_packed[8*96 +: 96];
                4'd9:  fin_acc_rsp_data <= acc_rd_packed[9*96 +: 96];
                4'd10: fin_acc_rsp_data <= acc_rd_packed[10*96 +: 96];
                4'd11: fin_acc_rsp_data <= acc_rd_packed[11*96 +: 96];
                4'd12: fin_acc_rsp_data <= acc_rd_packed[12*96 +: 96];
                4'd13: fin_acc_rsp_data <= acc_rd_packed[13*96 +: 96];
                4'd14: fin_acc_rsp_data <= acc_rd_packed[14*96 +: 96];
                default: fin_acc_rsp_data <= acc_rd_packed[15*96 +: 96];
            endcase
        end
    end
end

endmodule

`default_nettype wire
