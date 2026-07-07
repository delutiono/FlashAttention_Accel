`timescale 1ns/1ps
`default_nettype none

// 2-lane ACC normalization pipe with split multiplier for 300MHz timing.
// ACC: signed Q*.30, INV: unsigned Q2.30, product: signed Q*.60.
// output_shift dynamic: 52=Q8.8, 50=Q6.10, 48=Q4.12.
// Pipeline: M1(reg inputs) -> M2(multiply) -> R(round+shift) -> S(saturate)
module output_norm_pipe #(
    parameter TOKEN_WIDTH = 8,
    parameter LANES = 2,
    parameter ACC_WIDTH = 48,
    parameter INV_WIDTH = 32,
    parameter OUT_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [ACC_WIDTH*LANES-1:0] in_acc,
    input  wire [INV_WIDTH-1:0]         in_inv,
    input  wire [TOKEN_WIDTH-1:0]       in_token,
    input  wire [5:0]                   output_shift,
    output wire                         out_valid,
    input  wire                         out_ready,
    output wire [OUT_WIDTH*LANES-1:0]   out_data,
    output wire [TOKEN_WIDTH-1:0]       out_token
);

localparam PRODUCT_WIDTH = ACC_WIDTH + INV_WIDTH;
localparam SHIFTED_WIDTH = 32;

reg valid_m1_reg;
reg valid_m2_reg;
reg valid_r_reg;
reg valid_s_reg;
reg [TOKEN_WIDTH-1:0] token_m1_reg;
reg [TOKEN_WIDTH-1:0] token_m2_reg;
reg [TOKEN_WIDTH-1:0] token_r_reg;
reg [TOKEN_WIDTH-1:0] token_s_reg;
reg signed [ACC_WIDTH-1:0] acc_m1_reg [0:LANES-1];
reg [INV_WIDTH-1:0] inv_m1_reg;
reg [5:0] shift_m1_reg;
reg [5:0] shift_m2_reg;
reg signed [PRODUCT_WIDTH-1:0] product_reg [0:LANES-1];
reg signed [SHIFTED_WIDTH-1:0] shifted_reg [0:LANES-1];
reg signed [OUT_WIDTH-1:0] sat_reg [0:LANES-1];

wire pipe_ready = !valid_s_reg || out_ready;
assign in_ready = pipe_ready;
assign out_valid = valid_s_reg;
assign out_token = token_s_reg;

genvar out_i;
generate
    for (out_i = 0; out_i < LANES; out_i = out_i + 1) begin : g_out_pack
        assign out_data[out_i*OUT_WIDTH +: OUT_WIDTH] = sat_reg[out_i];
    end
endgenerate

function signed [SHIFTED_WIDTH-1:0] round_shift_product;
    input signed [PRODUCT_WIDTH-1:0] value;
    input [5:0] shift;
    reg signed [PRODUCT_WIDTH:0] extended;
    begin
        extended = {value[PRODUCT_WIDTH-1], value};
        if (value[PRODUCT_WIDTH-1])
            extended = extended + ($signed(1) <<< (shift - 1)) - 1;
        else
            extended = extended + ($signed(1) <<< (shift - 1));
        round_shift_product = extended >>> shift;
    end
endfunction

function signed [OUT_WIDTH-1:0] sat_int16;
    input signed [SHIFTED_WIDTH-1:0] value;
    begin
        if ($signed(value) > 32'sh7fff)
            sat_int16 = 16'sh7fff;
        else if ($signed(value) < -32'sh8000)
            sat_int16 = -16'sh8000;
        else
            sat_int16 = value[15:0];
    end
endfunction

integer i;
always @(posedge clk) begin
    if (!rst_n) begin
        valid_m1_reg <= 1'b0;
        valid_m2_reg <= 1'b0;
        valid_r_reg <= 1'b0;
        valid_s_reg <= 1'b0;
        token_m1_reg <= {TOKEN_WIDTH{1'b0}};
        token_m2_reg <= {TOKEN_WIDTH{1'b0}};
        token_r_reg <= {TOKEN_WIDTH{1'b0}};
        token_s_reg <= {TOKEN_WIDTH{1'b0}};
        inv_m1_reg <= {INV_WIDTH{1'b0}};
        shift_m1_reg <= 6'd0;
        shift_m2_reg <= 6'd0;
        for (i = 0; i < LANES; i = i + 1) begin
            acc_m1_reg[i] <= {ACC_WIDTH{1'b0}};
            product_reg[i] <= {PRODUCT_WIDTH{1'b0}};
            shifted_reg[i] <= {SHIFTED_WIDTH{1'b0}};
            sat_reg[i] <= {OUT_WIDTH{1'b0}};
        end
    end else if (pipe_ready) begin
        // M1: register multiplier inputs (splits 48x32 multiply retiming boundary)
        valid_m1_reg <= in_valid;
        token_m1_reg <= in_token;
        if (in_valid) begin
            for (i = 0; i < LANES; i = i + 1) begin
                acc_m1_reg[i] <= in_acc[i*ACC_WIDTH +: ACC_WIDTH];
            end
            inv_m1_reg <= in_inv;
            shift_m1_reg <= output_shift;
        end

        // M2: multiply from registered inputs
        valid_m2_reg <= valid_m1_reg;
        token_m2_reg <= token_m1_reg;
        shift_m2_reg <= shift_m1_reg;
        for (i = 0; i < LANES; i = i + 1) begin
            product_reg[i] <= $signed(acc_m1_reg[i]) * $signed({1'b0, inv_m1_reg});
        end

        // R: round + shift
        valid_r_reg <= valid_m2_reg;
        token_r_reg <= token_m2_reg;
        for (i = 0; i < LANES; i = i + 1) begin
            shifted_reg[i] <= round_shift_product(product_reg[i], shift_m2_reg);
        end

        // S: saturate
        valid_s_reg <= valid_r_reg;
        token_s_reg <= token_r_reg;
        for (i = 0; i < LANES; i = i + 1) begin
            sat_reg[i] <= sat_int16(shifted_reg[i]);
        end
    end
end

endmodule

`default_nettype wire
