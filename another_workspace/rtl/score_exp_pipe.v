`timescale 1ns/1ps
`default_nettype none

// dot 为 Q16.16，scale 为 unsigned Q0.16，score/m 为 signed Q16.16。
// alpha/beta 为 unsigned Q1.15。exp 常量 ROM 为 16-bank 两级注册结构。
module score_exp_pipe #(
    parameter TOKEN_WIDTH = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    in_valid,
    output wire                    in_ready,
    input  wire signed [47:0]      in_dot,
    input  wire [15:0]             in_scale,
    input  wire signed [31:0]      in_m_old,
    input  wire                    in_mask_valid,
    input  wire                    in_dropout_en,
    input  wire [31:0]             in_dropout_seed,
    input  wire [15:0]             in_dropout_prob,
    input  wire [TOKEN_WIDTH-1:0]  in_token,
    output reg                     out_valid,
    output reg signed [31:0]       out_score,
    output reg signed [31:0]       out_m_new,
    output reg [15:0]              out_alpha,
    output reg [15:0]              out_beta,
    output reg [TOKEN_WIDTH-1:0]   out_token
);

localparam signed [31:0] SCORE_MAX = 32'sh7fffffff;
localparam signed [31:0] SCORE_MIN = -32'sh80000000;

reg                    v0, v1, v2;
reg signed [64:0]      product_s0;
reg signed [48:0]      scaled_s1;
reg signed [31:0]      score_s2;
reg signed [31:0]      m_old_s0, m_old_s1, m_old_s2;
reg [TOKEN_WIDTH-1:0]  token_s0, token_s1, token_s2;
reg                    mask_v0, mask_v1, mask_v2;
reg                    dropout_v0, dropout_v1, dropout_v2;
reg [31:0]             lfsr;
reg [31:0]             last_seed;
reg signed [31:0]      score_side_s0, score_side_s1;
reg signed [31:0]      m_side_s0, m_side_s1;
reg [TOKEN_WIDTH-1:0]  token_side_s0, token_side_s1;
reg                    score_wins_s0, score_wins_s1;
reg                    exp_zero_s0, exp_zero_s1;
reg                    mask_side_s0, mask_side_s1;
reg                    dropout_side_s0, dropout_side_s1;

wire signed [31:0] score_sat_s1;
wire signed [31:0] m_new_comb;
wire signed [31:0] losing_diff_comb;
wire [10:0] exp_addr_comb;
wire exp_zero_comb;
wire rom_valid;
wire [15:0] rom_data;

function signed [48:0] round_shift16;
    input signed [64:0] value;
    reg signed [65:0] magnitude;
    begin
        if (value >= 0)
            round_shift16 = (value + 65'sd32768) >>> 16;
        else begin
            magnitude = -$signed({value[64], value});
            round_shift16 = -((magnitude + 66'sd32768) >>> 16);
        end
    end
endfunction

assign in_ready = 1'b1;
assign score_sat_s1 = (scaled_s1 > $signed({1'b0, SCORE_MAX})) ? SCORE_MAX :
                      (scaled_s1 < $signed({{17{1'b1}}, SCORE_MIN})) ? SCORE_MIN :
                      scaled_s1[31:0];
assign m_new_comb = (score_s2 > m_old_s2) ? score_s2 : m_old_s2;
assign losing_diff_comb = (score_s2 > m_old_s2) ?
                          (m_old_s2 - score_s2) : (score_s2 - m_old_s2);
assign exp_zero_comb = (losing_diff_comb <= -32'sh00100000);
assign exp_addr_comb = exp_zero_comb ? 11'h7ff : ((-losing_diff_comb) >> 9);

score_exp_banked_rom u_exp_rom (
    .clk(clk), .rst_n(rst_n), .in_valid(v2), .in_addr(exp_addr_comb),
    .out_valid(rom_valid), .out_data(rom_data)
);

always @(posedge clk) begin
    if (!rst_n) begin
        v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0;
        mask_v0 <= 1'b0; mask_v1 <= 1'b0; mask_v2 <= 1'b0;
        mask_side_s0 <= 1'b0; mask_side_s1 <= 1'b0;
        dropout_v0 <= 1'b0; dropout_v1 <= 1'b0; dropout_v2 <= 1'b0;
        dropout_side_s0 <= 1'b0; dropout_side_s1 <= 1'b0;
        lfsr <= 32'd1;
        last_seed <= 32'd0;
        out_valid <= 1'b0;
        out_score <= 32'sd0;
        out_m_new <= 32'sd0;
        out_alpha <= 16'd0;
        out_beta <= 16'd0;
        out_token <= {TOKEN_WIDTH{1'b0}};
    end else begin
        v0 <= in_valid;
        v1 <= v0;
        v2 <= v1;
        out_valid <= rom_valid;

        if (in_valid) begin
            product_s0 <= $signed(in_dot) * $signed({1'b0, in_scale});
            m_old_s0 <= in_m_old;
            token_s0 <= in_token;
            mask_v0 <= in_mask_valid;
            // LFSR: x^32 + x^22 + x^2 + x + 1
            if (in_dropout_seed != last_seed) begin
                lfsr <= in_dropout_seed;
                last_seed <= in_dropout_seed;
            end else if (in_dropout_en) begin
                lfsr <= {lfsr[30:0], lfsr[31]} ^ (lfsr[31] ? 32'h0040_0003 : 32'd0);
            end
            dropout_v0 <= in_dropout_en && (lfsr[15:0] < in_dropout_prob);
        end
        if (v0) begin
            // Q16.16 * Q0.16 -> Q16.32，round-to-nearest 后回到 Q16.16。
            scaled_s1 <= round_shift16(product_s0);
            m_old_s1 <= m_old_s0;
            token_s1 <= token_s0;
            mask_v1 <= mask_v0;
            dropout_v1 <= dropout_v0;
        end
        if (v1) begin
            score_s2 <= score_sat_s1;
            m_old_s2 <= m_old_s1;
            token_s2 <= token_s1;
            mask_v2 <= mask_v1;
            dropout_v2 <= dropout_v1;
        end
        if (v2) begin
            score_side_s0 <= score_s2;
            m_side_s0 <= mask_v2 ? m_old_s2 : m_new_comb;
            token_side_s0 <= token_s2;
            score_wins_s0 <= mask_v2 ? 1'b0 : (score_s2 > m_old_s2);
            exp_zero_s0 <= mask_v2 ? 1'b1 : exp_zero_comb;
            mask_side_s0 <= mask_v2;
            dropout_side_s0 <= dropout_v2;
        end
        score_side_s1 <= score_side_s0;
        m_side_s1 <= m_side_s0;
        token_side_s1 <= token_side_s0;
        score_wins_s1 <= score_wins_s0;
        exp_zero_s1 <= exp_zero_s0;
        mask_side_s1 <= mask_side_s0;
        dropout_side_s1 <= dropout_side_s0;
        if (rom_valid) begin
            out_score <= score_side_s1;
            out_m_new <= m_side_s1;
            out_alpha <= (mask_side_s1 || dropout_side_s1) ? 16'h8000 : (score_wins_s1 ? (exp_zero_s1 ? 16'd0 : rom_data) : 16'h8000);
            out_beta  <= (mask_side_s1 || dropout_side_s1) ? 16'd0   : (score_wins_s1 ? 16'h8000 : (exp_zero_s1 ? 16'd0 : rom_data));
            out_token <= token_side_s1;
        end
    end
end

endmodule

`default_nettype wire
