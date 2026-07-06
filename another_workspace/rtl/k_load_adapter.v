`timescale 1ns/1ps
`default_nettype none

module k_load_adapter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         page,
    input  wire         lowp_int8_mode,
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
reg       page_reg;
reg       lowp_second_half_reg;
reg [1:0] done_pending_reg;
reg [127:0] lowp_data_reg;
wire fire = in_valid && in_ready;
wire [5:0] last_beat = lowp_int8_mode ? 6'd31 : 6'd63;

assign in_ready = busy && !lowp_second_half_reg;
assign k_rw_write = 1'b1;
assign k_rw_wmask = 16'hffff;

function [127:0] unpack_int8x8_to_q8_8;
    input [63:0] bytes;
    integer i;
    begin
        for (i = 0; i < 8; i = i + 1)
            unpack_int8x8_to_q8_8[i*16 +: 16] = {bytes[i*8 +: 8], 8'd0};
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        busy <= 1'b0;
        done <= 1'b0;
        k_rw_valid <= 1'b0;
        k_rw_pair <= 2'd0;
        k_rw_addr <= 5'd0;
        k_rw_data <= 128'd0;
        beat_count_reg <= 6'd0;
        page_reg <= 1'b0;
        lowp_second_half_reg <= 1'b0;
        done_pending_reg <= 2'b00;
        lowp_data_reg <= 128'd0;
        error <= 1'b0;
    end else begin
        done <= done_pending_reg[1];
        done_pending_reg <= {done_pending_reg[0], 1'b0};
        k_rw_valid <= 1'b0;
        if (start && !busy) begin
            busy <= 1'b1;
            page_reg <= page;
            beat_count_reg <= 6'd0;
            lowp_second_half_reg <= 1'b0;
        end
        if (lowp_second_half_reg) begin
            k_rw_valid <= 1'b1;
            k_rw_pair <= {beat_count_reg[0], 1'b1};
            k_rw_addr <= {page_reg, beat_count_reg[4:1]};
            k_rw_data <= unpack_int8x8_to_q8_8(lowp_data_reg[127:64]);
            lowp_second_half_reg <= 1'b0;
            beat_count_reg <= beat_count_reg + 6'd1;
            if (beat_count_reg == last_beat) begin
                busy <= 1'b0;
                done_pending_reg[0] <= 1'b1;
            end
        end else if (fire) begin
            k_rw_valid <= 1'b1;
            if (lowp_int8_mode) begin
                k_rw_pair <= {beat_count_reg[0], 1'b0};
                k_rw_addr <= {page_reg, beat_count_reg[4:1]};
                k_rw_data <= unpack_int8x8_to_q8_8(in_data[63:0]);
                lowp_data_reg <= in_data;
                lowp_second_half_reg <= 1'b1;
            end else begin
                k_rw_pair <= beat_count_reg[1:0];
                k_rw_addr <= {page_reg, beat_count_reg[5:3], beat_count_reg[2]};
                k_rw_data <= in_data;
                beat_count_reg <= beat_count_reg + 6'd1;
                if (beat_count_reg == last_beat) begin
                    busy <= 1'b0;
                    done_pending_reg[0] <= 1'b1;
                end
            end
            if (beat_count_reg == last_beat) begin
                if (!in_last) error <= 1'b1;
            end else if (in_last) begin
                error <= 1'b1;
            end
        end
    end
end

endmodule

`default_nettype wire
