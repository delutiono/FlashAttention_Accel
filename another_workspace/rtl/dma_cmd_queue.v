`timescale 1ns/1ps
`default_nettype none

module dma_cmd_queue #(
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = 64,
    parameter BYTES_WIDTH = 16,
    parameter TAG_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire [1:0]            in_kind,
    input  wire                  in_page,
    input  wire [ADDR_WIDTH-1:0] in_base_addr,
    input  wire [BYTES_WIDTH-1:0] in_bytes,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire [1:0]            out_kind,
    output wire                  out_page,
    output wire [ADDR_WIDTH-1:0] out_base_addr,
    output wire [BYTES_WIDTH-1:0] out_bytes,
    output wire [TAG_WIDTH-1:0]  out_tag,
    output wire [3:0]            occupancy
);

reg [1:0] kind_mem [0:DEPTH-1];
reg page_mem [0:DEPTH-1];
reg [ADDR_WIDTH-1:0] base_mem [0:DEPTH-1];
reg [BYTES_WIDTH-1:0] bytes_mem [0:DEPTH-1];
reg [TAG_WIDTH-1:0] tag_mem [0:DEPTH-1];
reg [2:0] wr_ptr_reg;
reg [2:0] rd_ptr_reg;
reg [3:0] count_reg;

wire push = in_valid && in_ready;
wire pop = out_valid && out_ready;

localparam [3:0] DEPTH_COUNT = DEPTH[3:0];

assign in_ready = (count_reg != DEPTH_COUNT);
assign out_valid = (count_reg != 4'd0);
assign out_kind = kind_mem[rd_ptr_reg];
assign out_page = page_mem[rd_ptr_reg];
assign out_base_addr = base_mem[rd_ptr_reg];
assign out_bytes = bytes_mem[rd_ptr_reg];
assign out_tag = tag_mem[rd_ptr_reg];
assign occupancy = count_reg;

always @(posedge clk) begin
    if (!rst_n) begin
        wr_ptr_reg <= 3'd0;
        rd_ptr_reg <= 3'd0;
        count_reg <= 4'd0;
    end else begin
        if (push) begin
            kind_mem[wr_ptr_reg] <= in_kind;
            page_mem[wr_ptr_reg] <= in_page;
            base_mem[wr_ptr_reg] <= in_base_addr;
            bytes_mem[wr_ptr_reg] <= in_bytes;
            tag_mem[wr_ptr_reg] <= in_tag;
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
