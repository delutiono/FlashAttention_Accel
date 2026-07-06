`timescale 1ns/1ps
`default_nettype none

module k_load_adapter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         page,
    output reg          busy,
    output reg          done,
    input  wire         in_valid,
    output wire         in_ready,
    input  wire [127:0] in_data,
    input  wire         in_last,
    output reg          k_rw_valid,
    output wire         k_rw_write,
    output reg  [1:0]   k_rw_pair,
    output reg  [4:0]   k_rw_addr,
    output wire [15:0]  k_rw_wmask,
    output reg  [127:0] k_rw_data,
    output reg          error
);

reg [5:0] beat_count_reg;
wire fire = in_valid && in_ready;

assign in_ready = busy;
assign k_rw_write = 1'b1;
assign k_rw_wmask = 16'hffff;

always @(posedge clk) begin
    if (!rst_n) begin
        busy <= 1'b0;
        done <= 1'b0;
        k_rw_valid <= 1'b0;
        k_rw_pair <= 2'd0;
        k_rw_addr <= 5'd0;
        k_rw_data <= 128'd0;
        beat_count_reg <= 6'd0;
        error <= 1'b0;
    end else begin
        done <= 1'b0;
        k_rw_valid <= 1'b0;
        if (start && !busy) begin
            busy <= 1'b1;
            beat_count_reg <= 6'd0;
        end
        if (fire) begin
            k_rw_valid <= 1'b1;
            k_rw_pair <= beat_count_reg[1:0];
            k_rw_addr <= {page, beat_count_reg[5:3], beat_count_reg[2]};
            k_rw_data <= in_data;
            beat_count_reg <= beat_count_reg + 6'd1;
            if (beat_count_reg == 6'd63) begin
                busy <= 1'b0;
                done <= 1'b1;
                if (!in_last)
                    error <= 1'b1;
            end else if (in_last) begin
                error <= 1'b1;
            end
        end
    end
end

endmodule

`default_nettype wire
