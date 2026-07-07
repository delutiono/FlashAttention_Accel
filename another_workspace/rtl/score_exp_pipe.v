`timescale 1ns/1ps
`default_nettype none

// dot 为 Q16.16，scale 为 unsigned Q0.16，score/m 为 signed Q16.16。
// alpha/beta 为 unsigned Q1.15。exp 常量 ROM 为 16-bank 两级注册结构。
// P3 timing: v0 仅捕获输入，v1 执行乘法，避免 48x16 乘法与上游
// dot_frontend 输出寄存器之间的长组合路径。
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

	reg                    v0, v1, v2, v3;
	reg signed [47:0]      dot_cap;
	reg [15:0]             scale_cap;
	reg signed [64:0]      product_s1;
	reg signed [48:0]      scaled_s2;
	reg signed [31:0]      score_s3;
	reg signed [31:0]      m_old_s0, m_old_s1, m_old_s2, m_old_s3;
	reg [TOKEN_WIDTH-1:0]  token_s0, token_s1, token_s2, token_s3;
	reg signed [31:0]      score_side_s0, score_side_s1;
	reg signed [31:0]      m_side_s0, m_side_s1;
	reg [TOKEN_WIDTH-1:0]  token_side_s0, token_side_s1;
	reg                    score_wins_s0, score_wins_s1;
	reg                    exp_zero_s0, exp_zero_s1;

	wire signed [31:0] score_sat_s2;
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
	assign score_sat_s2 = (scaled_s2 > $signed({1'b0, SCORE_MAX})) ? SCORE_MAX :
	                      (scaled_s2 < $signed({{17{1'b1}}, SCORE_MIN})) ? SCORE_MIN :
	                      scaled_s2[31:0];
	assign m_new_comb = (score_s3 > m_old_s3) ? score_s3 : m_old_s3;
	assign losing_diff_comb = (score_s3 > m_old_s3) ?
	                          (m_old_s3 - score_s3) : (score_s3 - m_old_s3);
	assign exp_zero_comb = (losing_diff_comb <= -32'sh00100000);
	assign exp_addr_comb = exp_zero_comb ? 11'h7ff : ((-losing_diff_comb) >> 9);

	score_exp_banked_rom u_exp_rom (
	    .clk(clk), .rst_n(rst_n), .in_valid(v3), .in_addr(exp_addr_comb),
	    .out_valid(rom_valid), .out_data(rom_data)
	);

	always @(posedge clk) begin
	    if (!rst_n) begin
	        v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0;
	        dot_cap <= 48'sd0;
	        scale_cap <= 16'd0;
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
	        v3 <= v2;
	        out_valid <= rom_valid;

	        // Stage 0 (v0): capture inputs only -- separates upstream
	        // dot_frontend register delay from the 48x16 multiplier.
	        if (in_valid) begin
	            dot_cap <= in_dot;
	            scale_cap <= in_scale;
	            m_old_s0 <= in_m_old;
	            token_s0 <= in_token;
	        end
	        // Stage 1 (v1): 48x16 multiply.
	        if (v0) begin
	            product_s1 <= $signed(dot_cap) * $signed({1'b0, scale_cap});
	            m_old_s1 <= m_old_s0;
	            token_s1 <= token_s0;
	        end
	        // Stage 2 (v2): round-to-nearest Q16.32 -> Q16.16.
	        if (v1) begin
	            scaled_s2 <= round_shift16(product_s1);
	            m_old_s2 <= m_old_s1;
	            token_s2 <= token_s1;
	        end
	        // Stage 3 (v3): saturation to Q16.16.
	        if (v2) begin
	            score_s3 <= score_sat_s2;
	            m_old_s3 <= m_old_s2;
	            token_s3 <= token_s2;
	        end
	        // Stage 4: m_new, losing_diff, exp_addr (feeds ROM).
	        if (v3) begin
	            score_side_s0 <= score_s3;
	            m_side_s0 <= m_new_comb;
	            token_side_s0 <= token_s3;
	            score_wins_s0 <= (score_s3 > m_old_s3);
	            exp_zero_s0 <= exp_zero_comb;
	        end
	        score_side_s1 <= score_side_s0;
	        m_side_s1 <= m_side_s0;
	        token_side_s1 <= token_side_s0;
	        score_wins_s1 <= score_wins_s0;
	        exp_zero_s1 <= exp_zero_s0;
	        if (rom_valid) begin
	            out_score <= score_side_s1;
	            out_m_new <= m_side_s1;
	            out_alpha <= score_wins_s1 ? (exp_zero_s1 ? 16'd0 : rom_data) : 16'h8000;
	            out_beta <= score_wins_s1 ? 16'h8000 : (exp_zero_s1 ? 16'd0 : rom_data);
	            out_token <= token_side_s1;
	        end
	    end
	end

endmodule

`default_nettype wire
