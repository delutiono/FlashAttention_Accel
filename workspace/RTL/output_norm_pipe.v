`timescale 1ns/1ps
`default_nettype none

// 2-lane ACC normalization pipe with split multiplier for 300MHz timing.
// ACC: signed Q*.30, INV: unsigned Q2.30, product: signed Q*.60.
// OUTPUT_SHIFT=52 for Q8.8 output; round-to-nearest, saturate to int16.
// Pipeline: M1(reg inputs) → M2(multiply) → R(round+shift) → S(saturate)
module output_norm_pipe #(
    parameter TOKEN_WIDTH = 8,
    parameter LANES = 2,
    parameter ACC_WIDTH = 48,
    parameter INV_WIDTH = 32,
    parameter OUT_WIDTH = 16,
    parameter OUTPUT_SHIFT = 52
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [ACC_WIDTH*LANES-1:0] in_acc,
    input  wire [INV_WIDTH-1:0]         in_inv,
    input  wire [TOKEN_WIDTH-1:0]       in_token,
    output wire                         out_valid,
    input  wire                         out_ready,
    output wire [OUT_WIDTH*LANES-1:0]   out_data,
    output wire [TOKEN_WIDTH-1:0]       out_token
);

localparam PRODUCT_WIDTH = ACC_WIDTH + INV_WIDTH;
localparam SHIFTED_WIDTH = PRODUCT_WIDTH - OUTPUT_SHIFT;

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
    reg signed [PRODUCT_WIDTH-1:0] biased;
    begin
        if (value[PRODUCT_WIDTH-1])
            biased = value + $signed({{(PRODUCT_WIDTH-OUTPUT_SHIFT){1'b0}}, 1'b1, {(OUTPUT_SHIFT-1){1'b0}}}) - {{(PRODUCT_WIDTH-1){1'b0}}, 1'b1};
        else
            biased = value + $signed({{(PRODUCT_WIDTH-OUTPUT_SHIFT){1'b0}}, 1'b1, {(OUTPUT_SHIFT-1){1'b0}}});
        round_shift_product = biased[PRODUCT_WIDTH-1:OUTPUT_SHIFT];
    end
endfunction

function signed [OUT_WIDTH-1:0] sat_q8_8;
    input signed [SHIFTED_WIDTH-1:0] value;
    reg signed [SHIFTED_WIDTH-1:0] max_v;
    reg signed [SHIFTED_WIDTH-1:0] min_v;
    begin
        max_v = {{(SHIFTED_WIDTH-15){1'b0}}, 15'h7fff};
        min_v = {1'b1, {(SHIFTED_WIDTH-1){1'b0}}};
        if (SHIFTED_WIDTH > OUT_WIDTH)
            min_v = {{(SHIFTED_WIDTH-OUT_WIDTH){1'b1}}, 1'b1, {(OUT_WIDTH-1){1'b0}}};
        if (value > max_v)
            sat_q8_8 = 16'sh7fff;
        else if (value < min_v)
            sat_q8_8 = -16'sh8000;
        else
            sat_q8_8 = value[OUT_WIDTH-1:0];
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
        end

        // M2: multiply from registered inputs
        valid_m2_reg <= valid_m1_reg;
        token_m2_reg <= token_m1_reg;
        for (i = 0; i < LANES; i = i + 1) begin
            product_reg[i] <= $signed(acc_m1_reg[i]) * $signed({1'b0, inv_m1_reg});
        end

        // R: round + shift
        valid_r_reg <= valid_m2_reg;
        token_r_reg <= token_m2_reg;
        for (i = 0; i < LANES; i = i + 1) begin
            shifted_reg[i] <= round_shift_product(product_reg[i]);
        end

        // S: saturate
        valid_s_reg <= valid_r_reg;
        token_s_reg <= token_r_reg;
        for (i = 0; i < LANES; i = i + 1) begin
            sat_reg[i] <= sat_q8_8(shifted_reg[i]);
        end
    end
end

endmodule

`default_nettype wire
