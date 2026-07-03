`timescale 1ns/1ps
`default_nettype none

// baseline4 32-lane、2-phase dot 前端。
// Q/K 为 signed Q8.8；乘积为 signed Q16.16；64 lane 累加输出 48 bit，
// 小数位仍为 16。Q/K 宽读始终限制在本模块内部，不形成层级超宽端口。
module dot_frontend #(
    parameter TOKEN_WIDTH = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    q_load_valid,
    input  wire [1:0]              q_load_pair,
    input  wire [4:0]              q_load_addr,
    input  wire [15:0]             q_load_wmask,
    input  wire [127:0]            q_load_data,
    input  wire                    q_ext_valid,
    input  wire                    q_ext_write,
    input  wire [1:0]              q_ext_pair,
    input  wire [4:0]              q_ext_addr,
    input  wire [15:0]             q_ext_wmask,
    input  wire [127:0]            q_ext_wdata,
    output wire                    q_ext_rvalid,
    output wire [127:0]            q_ext_rdata,
    input  wire                    k_load_valid,
    input  wire [1:0]              k_load_pair,
    input  wire [4:0]              k_load_addr,
    input  wire [15:0]             k_load_wmask,
    input  wire [127:0]            k_load_data,

    input  wire                    in_valid,
    output wire                    in_ready,
    input  wire                    in_q_page,
    input  wire [2:0]              in_q_row,
    input  wire                    in_k_page,
    input  wire [2:0]              in_k_row,
    input  wire [TOKEN_WIDTH-1:0]  in_token,

    output reg                     out_valid,
    output reg signed [47:0]       out_dot,
    output reg [TOKEN_WIDTH-1:0]   out_token
);

localparam integer BANKS = 8;
localparam integer LANES_PER_BANK = 4;

reg                    phase_active_reg;
reg                    phase_q_page_reg;
reg [2:0]              phase_q_row_reg;
reg                    phase_k_page_reg;
reg [2:0]              phase_k_row_reg;
reg [TOKEN_WIDTH-1:0]  phase_token_reg;

wire                   issue_phase;
wire                   issue_phase_sel;
wire [4:0]             q_rd_addr;
wire [4:0]             k_rd_addr;
wire                   q_rd_valid;
wire                   k_rd_valid;
wire [63:0]            q_bank_data [0:BANKS-1];
wire [63:0]            k_bank_data [0:BANKS-1];

reg [1:0]              rd_valid_pipe;
reg [1:0]              rd_phase_pipe;
reg [TOKEN_WIDTH-1:0]  rd_token_pipe [0:1];

reg                    mul_valid_reg;
reg                    mul_phase_reg;
reg [TOKEN_WIDTH-1:0]  mul_token_reg;
reg signed [31:0]      product_reg [0:BANKS*LANES_PER_BANK-1];

reg                    bank_valid_reg;
reg                    bank_phase_reg;
reg [TOKEN_WIDTH-1:0]  bank_token_reg;
reg signed [33:0]      bank_sum_reg [0:BANKS-1];

reg                    reduce0_valid_reg;
reg                    reduce0_phase_reg;
reg [TOKEN_WIDTH-1:0]  reduce0_token_reg;
reg signed [34:0]      reduce0_sum_reg [0:3];

reg                    reduce1_valid_reg;
reg                    reduce1_phase_reg;
reg [TOKEN_WIDTH-1:0]  reduce1_token_reg;
reg signed [35:0]      reduce1_sum_reg [0:1];

reg                    half_valid_reg;
reg                    half_phase_reg;
reg [TOKEN_WIDTH-1:0]  half_token_reg;
reg signed [36:0]      half_sum_reg;
reg                    saved_half_valid_reg;
reg [TOKEN_WIDTH-1:0]  saved_half_token_reg;
reg signed [47:0]      saved_half_sum_reg;

wire signed [15:0] q_lane [0:BANKS*LANES_PER_BANK-1];
wire signed [15:0] k_lane [0:BANKS*LANES_PER_BANK-1];
wire signed [47:0] half_sum_ext;
wire signed [48:0] full_sum_ext;
wire q_port_valid = q_ext_valid || q_load_valid;
wire q_port_write = q_ext_valid ? q_ext_write : 1'b1;
wire [1:0] q_port_pair = q_ext_valid ? q_ext_pair : q_load_pair;
wire [4:0] q_port_addr = q_ext_valid ? q_ext_addr : q_load_addr;
wire [15:0] q_port_wmask = q_ext_valid ? q_ext_wmask : q_load_wmask;
wire [127:0] q_port_wdata = q_ext_valid ? q_ext_wdata : q_load_data;

integer i;

function signed [33:0] sum_four_products;
    input signed [31:0] p0;
    input signed [31:0] p1;
    input signed [31:0] p2;
    input signed [31:0] p3;
    reg signed [32:0] pair0;
    reg signed [32:0] pair1;
    begin
        pair0 = $signed({p0[31], p0}) + $signed({p1[31], p1});
        pair1 = $signed({p2[31], p2}) + $signed({p3[31], p3});
        sum_four_products = $signed({pair0[32], pair0}) +
                            $signed({pair1[32], pair1});
    end
endfunction

assign in_ready = !phase_active_reg;
assign issue_phase = phase_active_reg || (in_valid && in_ready);
assign issue_phase_sel = phase_active_reg;
assign q_rd_addr = phase_active_reg ?
    {phase_q_page_reg, phase_q_row_reg, 1'b1} :
    {in_q_page, in_q_row, 1'b0};
assign k_rd_addr = phase_active_reg ?
    {phase_k_page_reg, phase_k_row_reg, 1'b1} :
    {in_k_page, in_k_row, 1'b0};

assign half_sum_ext = {{11{half_sum_reg[36]}}, half_sum_reg};
assign full_sum_ext = $signed({saved_half_sum_reg[47], saved_half_sum_reg}) +
                      $signed({half_sum_ext[47], half_sum_ext});

genvar bank_idx;
generate
    for (bank_idx = 0; bank_idx < BANKS; bank_idx = bank_idx + 1) begin : g_lane_unpack
        genvar lane_idx;
        for (lane_idx = 0; lane_idx < LANES_PER_BANK; lane_idx = lane_idx + 1) begin : g_lane
            localparam integer FLAT_LANE = bank_idx * LANES_PER_BANK + lane_idx;
            assign q_lane[FLAT_LANE] = $signed(q_bank_data[bank_idx][lane_idx*16 +: 16]);
            assign k_lane[FLAT_LANE] = $signed(k_bank_data[bank_idx][lane_idx*16 +: 16]);
        end
    end
endgenerate

qk_sram_cluster u_q_sram (
    .clk(clk), .rst_n(rst_n),
    .rw_valid(q_port_valid), .rw_write(q_port_write), .rw_pair(q_port_pair),
    .rw_addr(q_port_addr), .rw_wmask(q_port_wmask), .rw_wdata(q_port_wdata),
    .rw_rvalid(q_ext_rvalid), .rw_rdata(q_ext_rdata),
    .wide_rd_en(issue_phase), .wide_rd_addr(q_rd_addr), .wide_rd_valid(q_rd_valid),
    .wide_rd_data0(q_bank_data[0]), .wide_rd_data1(q_bank_data[1]),
    .wide_rd_data2(q_bank_data[2]), .wide_rd_data3(q_bank_data[3]),
    .wide_rd_data4(q_bank_data[4]), .wide_rd_data5(q_bank_data[5]),
    .wide_rd_data6(q_bank_data[6]), .wide_rd_data7(q_bank_data[7])
);

qk_sram_cluster u_k_sram (
    .clk(clk), .rst_n(rst_n),
    .rw_valid(k_load_valid), .rw_write(1'b1), .rw_pair(k_load_pair),
    .rw_addr(k_load_addr), .rw_wmask(k_load_wmask), .rw_wdata(k_load_data),
    .rw_rvalid(), .rw_rdata(),
    .wide_rd_en(issue_phase), .wide_rd_addr(k_rd_addr), .wide_rd_valid(k_rd_valid),
    .wide_rd_data0(k_bank_data[0]), .wide_rd_data1(k_bank_data[1]),
    .wide_rd_data2(k_bank_data[2]), .wide_rd_data3(k_bank_data[3]),
    .wide_rd_data4(k_bank_data[4]), .wide_rd_data5(k_bank_data[5]),
    .wide_rd_data6(k_bank_data[6]), .wide_rd_data7(k_bank_data[7])
);

always @(posedge clk) begin
    if (!rst_n) begin
        phase_active_reg <= 1'b0;
        phase_q_page_reg <= 1'b0;
        phase_q_row_reg <= 3'd0;
        phase_k_page_reg <= 1'b0;
        phase_k_row_reg <= 3'd0;
        phase_token_reg <= {TOKEN_WIDTH{1'b0}};
        rd_valid_pipe <= 2'b00;
        rd_phase_pipe <= 2'b00;
        rd_token_pipe[0] <= {TOKEN_WIDTH{1'b0}};
        rd_token_pipe[1] <= {TOKEN_WIDTH{1'b0}};
        mul_valid_reg <= 1'b0;
        bank_valid_reg <= 1'b0;
        reduce0_valid_reg <= 1'b0;
        reduce1_valid_reg <= 1'b0;
        half_valid_reg <= 1'b0;
        saved_half_valid_reg <= 1'b0;
        out_valid <= 1'b0;
        out_dot <= 48'sd0;
        out_token <= {TOKEN_WIDTH{1'b0}};
    end else begin
        out_valid <= 1'b0;

        if (in_valid && in_ready) begin
            phase_active_reg <= 1'b1;
            phase_q_page_reg <= in_q_page;
            phase_q_row_reg <= in_q_row;
            phase_k_page_reg <= in_k_page;
            phase_k_row_reg <= in_k_row;
            phase_token_reg <= in_token;
        end else if (phase_active_reg) begin
            phase_active_reg <= 1'b0;
        end

        rd_valid_pipe[0] <= issue_phase;
        rd_valid_pipe[1] <= rd_valid_pipe[0];
        rd_phase_pipe[0] <= issue_phase_sel;
        rd_phase_pipe[1] <= rd_phase_pipe[0];
        rd_token_pipe[0] <= phase_active_reg ? phase_token_reg : in_token;
        rd_token_pipe[1] <= rd_token_pipe[0];

        mul_valid_reg <= rd_valid_pipe[1] && q_rd_valid && k_rd_valid;
        mul_phase_reg <= rd_phase_pipe[1];
        mul_token_reg <= rd_token_pipe[1];
        if (rd_valid_pipe[1] && q_rd_valid && k_rd_valid) begin
            for (i = 0; i < BANKS*LANES_PER_BANK; i = i + 1) begin
                product_reg[i] <= q_lane[i] * k_lane[i];
            end
        end

        bank_valid_reg <= mul_valid_reg;
        bank_phase_reg <= mul_phase_reg;
        bank_token_reg <= mul_token_reg;
        for (i = 0; i < BANKS; i = i + 1) begin
            bank_sum_reg[i] <= sum_four_products(
                product_reg[i*4+0], product_reg[i*4+1],
                product_reg[i*4+2], product_reg[i*4+3]);
        end

        reduce0_valid_reg <= bank_valid_reg;
        reduce0_phase_reg <= bank_phase_reg;
        reduce0_token_reg <= bank_token_reg;
        for (i = 0; i < 4; i = i + 1) begin
            reduce0_sum_reg[i] <=
                $signed({bank_sum_reg[i*2][33], bank_sum_reg[i*2]}) +
                $signed({bank_sum_reg[i*2+1][33], bank_sum_reg[i*2+1]});
        end

        reduce1_valid_reg <= reduce0_valid_reg;
        reduce1_phase_reg <= reduce0_phase_reg;
        reduce1_token_reg <= reduce0_token_reg;
        for (i = 0; i < 2; i = i + 1) begin
            reduce1_sum_reg[i] <=
                $signed({reduce0_sum_reg[i*2][34], reduce0_sum_reg[i*2]}) +
                $signed({reduce0_sum_reg[i*2+1][34], reduce0_sum_reg[i*2+1]});
        end

        half_valid_reg <= reduce1_valid_reg;
        half_phase_reg <= reduce1_phase_reg;
        half_token_reg <= reduce1_token_reg;
        half_sum_reg <= $signed({reduce1_sum_reg[0][35], reduce1_sum_reg[0]}) +
                        $signed({reduce1_sum_reg[1][35], reduce1_sum_reg[1]});

        if (half_valid_reg) begin
            if (!half_phase_reg) begin
                saved_half_valid_reg <= 1'b1;
                saved_half_token_reg <= half_token_reg;
                saved_half_sum_reg <= half_sum_ext;
            end else begin
                out_valid <= saved_half_valid_reg && (saved_half_token_reg == half_token_reg);
                out_dot <= full_sum_ext[47:0];
                out_token <= half_token_reg;
                saved_half_valid_reg <= 1'b0;
            end
        end
    end
end

endmodule

`default_nettype wire
