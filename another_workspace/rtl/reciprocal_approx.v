`timescale 1ns/1ps
`default_nettype none

// 48-bit unsigned/signed-safe l(Q*.30) -> unsigned Q2.30 reciprocal。
// 为保证可综合性，第一版采用定长 restoring divider，不使用运行时除法。
// out_inv = saturate_u32((1 << 60) / in_l)。
//
// P4 timing: each divider iteration split into two phases:
//   Phase A (compare):  rem_ge_denom = (rem_shift >= denom_ext)  -> registered
//   Phase B (subtract): rem_next = rem_ge_denom ? (rem_shift - denom_ext) : rem_shift
// Iterations double from 61 to 122; throughput impact is negligible because
// the reciprocal unit is not on the critical throughput path.
module reciprocal_approx #(
    parameter TOKEN_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire signed [47:0]    in_l,
    input  wire [TOKEN_WIDTH-1:0] in_token,
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire [31:0]           out_inv,
    output wire [TOKEN_WIDTH-1:0] out_token,
    output wire                  error_zero_l
);

	localparam [1:0] ST_IDLE = 2'd0;
	localparam [1:0] ST_DIV  = 2'd1;
	localparam [1:0] ST_OUT  = 2'd2;

	reg [1:0] state_reg;
	reg [6:0] bit_idx_reg;
	reg [47:0] denom_reg;
	reg [60:0] dividend_reg;
	reg [60:0] quotient_reg;
	reg [61:0] rem_reg;
	reg [TOKEN_WIDTH-1:0] token_reg;
	reg [31:0] inv_reg;
	reg zero_l_reg;
	reg overflow_reg;

	// P4: divider phase bit (0 = compare, 1 = subtract).
	reg div_phase_reg;
	reg rem_ge_denom_reg;

	wire signed [47:0] l_abs_signed = in_l[47] ? -in_l : in_l;
	wire [47:0] l_abs = l_abs_signed[47:0];
	wire [61:0] rem_shift = {rem_reg[60:0], dividend_reg[60]};
	wire [61:0] denom_ext = {14'd0, denom_reg};
	wire rem_ge_denom_comb = (rem_shift >= denom_ext);
	wire [61:0] rem_next_comb = rem_ge_denom_reg ? (rem_shift - denom_ext) : rem_shift;
	wire [60:0] quotient_next_comb = {quotient_reg[59:0], rem_ge_denom_reg};

	assign in_ready = (state_reg == ST_IDLE);
	assign out_valid = (state_reg == ST_OUT);
	assign out_inv = inv_reg;
	assign out_token = token_reg;
	assign error_zero_l = out_valid && zero_l_reg;

	always @(posedge clk) begin
	    if (!rst_n) begin
	        state_reg <= ST_IDLE;
	        bit_idx_reg <= 7'd0;
	        denom_reg <= 48'd0;
	        dividend_reg <= 61'd0;
	        quotient_reg <= 61'd0;
	        rem_reg <= 62'd0;
	        token_reg <= {TOKEN_WIDTH{1'b0}};
	        inv_reg <= 32'd0;
	        zero_l_reg <= 1'b0;
	        overflow_reg <= 1'b0;
	        div_phase_reg <= 1'b0;
	        rem_ge_denom_reg <= 1'b0;
	    end else begin
	        case (state_reg)
	            ST_IDLE: begin
	                if (in_valid) begin
	                    token_reg <= in_token;
	                    zero_l_reg <= (l_abs == 48'd0);
	                    overflow_reg <= 1'b0;
	                    bit_idx_reg <= 7'd0;
	                    rem_reg <= 62'd0;
	                    quotient_reg <= 61'd0;
	                    dividend_reg <= {1'b1, 60'd0};
	                    denom_reg <= l_abs;
	                    div_phase_reg <= 1'b0;
	                    rem_ge_denom_reg <= 1'b0;
	                    if (l_abs == 48'd0) begin
	                        inv_reg <= 32'hffff_ffff;
	                        state_reg <= ST_OUT;
	                    end else begin
	                        state_reg <= ST_DIV;
	                    end
	                end
	            end
	            ST_DIV: begin
	                if (!div_phase_reg) begin
	                    // Phase A: 62-bit comparison only.
	                    rem_ge_denom_reg <= rem_ge_denom_comb;
	                    div_phase_reg <= 1'b1;
	                end else begin
	                    // Phase B: subtract and shift using registered compare.
	                    rem_reg <= rem_next_comb;
	                    quotient_reg <= quotient_next_comb;
	                    dividend_reg <= {dividend_reg[59:0], 1'b0};
	                    div_phase_reg <= 1'b0;
	                    bit_idx_reg <= bit_idx_reg + 7'd1;
	                    if (bit_idx_reg == 7'd60) begin
	                        inv_reg <= (quotient_next_comb[60:32] != 29'd0) ? 32'hffff_ffff : quotient_next_comb[31:0];
	                        overflow_reg <= (quotient_next_comb[60:32] != 29'd0);
	                        state_reg <= ST_OUT;
	                    end
	                end
	            end
	            ST_OUT: begin
	                if (out_ready)
	                    state_reg <= ST_IDLE;
	            end
	            default: state_reg <= ST_IDLE;
	        endcase
	    end
	end

endmodule

`default_nettype wire
