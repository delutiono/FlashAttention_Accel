`timescale 1ns/1ps
`default_nettype none

module update_token_fifo #(
    parameter DEPTH = 8,
    parameter TOKEN_WIDTH = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    in_valid,
    output wire                    in_ready,
    input  wire signed [31:0]      in_m_new,
    input  wire [15:0]             in_alpha,
    input  wire [15:0]             in_beta,
    input  wire [TOKEN_WIDTH-1:0]  in_token,
    output wire                    out_valid,
    input  wire                    out_ready,
    output wire signed [31:0]      out_m_new,
    output wire [15:0]             out_alpha,
    output wire [15:0]             out_beta,
    output wire [TOKEN_WIDTH-1:0]  out_token,
    output wire [3:0]              occupancy
);

reg signed [31:0] m_mem [0:DEPTH-1];
reg [15:0] alpha_mem [0:DEPTH-1];
reg [15:0] beta_mem [0:DEPTH-1];
reg [TOKEN_WIDTH-1:0] token_mem [0:DEPTH-1];
reg [2:0] wr_ptr_reg;
reg [2:0] rd_ptr_reg;
reg [3:0] count_reg;
wire push;
wire pop;

assign in_ready = (count_reg != DEPTH);
assign out_valid = (count_reg != 0);
assign push = in_valid && in_ready;
assign pop = out_valid && out_ready;
assign out_m_new = m_mem[rd_ptr_reg];
assign out_alpha = alpha_mem[rd_ptr_reg];
assign out_beta = beta_mem[rd_ptr_reg];
assign out_token = token_mem[rd_ptr_reg];
assign occupancy = count_reg;

always @(posedge clk) begin
    if (!rst_n) begin
        wr_ptr_reg <= 3'd0;
        rd_ptr_reg <= 3'd0;
        count_reg <= 4'd0;
    end else begin
        if (push) begin
            m_mem[wr_ptr_reg] <= in_m_new;
            alpha_mem[wr_ptr_reg] <= in_alpha;
            beta_mem[wr_ptr_reg] <= in_beta;
            token_mem[wr_ptr_reg] <= in_token;
            wr_ptr_reg <= wr_ptr_reg + 3'd1;
        end
        if (pop)
            rd_ptr_reg <= rd_ptr_reg + 3'd1;
        case ({push, pop})
            2'b10: count_reg <= count_reg + 4'd1;
            2'b01: count_reg <= count_reg - 4'd1;
            default: count_reg <= count_reg;
        endcase
    end
end

endmodule

`default_nettype wire
