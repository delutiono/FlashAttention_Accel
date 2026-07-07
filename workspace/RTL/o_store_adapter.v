`timescale 1ns/1ps
`default_nettype none

module o_store_adapter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         page,
    output reg          busy,
    output reg          done,
    output reg          q_rw_valid,
    output wire         q_rw_write,
    output reg  [1:0]   q_rw_pair,
    output reg  [5:0]   q_rw_addr,
    input  wire         q_rw_rvalid,
    input  wire [127:0] q_rw_rdata,
    output wire         wr_valid,
    input  wire         wr_ready,
    output wire [127:0] wr_data,
    output wire [15:0]  wr_strb,
    output wire         wr_last
);

localparam integer RSP_FIFO_DEPTH = 4;
localparam [3:0] RSP_FIFO_DEPTH_VALUE = 4'd4;
localparam [3:0] RSP_FIFO_ISSUE_LIMIT = 4'd3;

reg [6:0] req_count_reg;
reg [6:0] rsp_count_reg;
reg [1:0] outstanding_reg;
reg [127:0] rsp_fifo_data [0:RSP_FIFO_DEPTH-1];
reg         rsp_fifo_last [0:RSP_FIFO_DEPTH-1];
reg [1:0]   rsp_fifo_wr_ptr;
reg [1:0]   rsp_fifo_rd_ptr;
reg [2:0]   rsp_fifo_count;

wire [3:0] reserved_slots = {1'b0, rsp_fifo_count} + {2'b00, outstanding_reg};
wire can_issue = busy && (req_count_reg != 7'd64) &&
                 (reserved_slots < RSP_FIFO_ISSUE_LIMIT);
wire rsp_push = q_rw_rvalid;
wire out_fire = wr_valid && wr_ready;

assign q_rw_write = 1'b0;
assign wr_strb = 16'hffff;
assign wr_valid = (rsp_fifo_count != 3'd0);
assign wr_data = rsp_fifo_data[rsp_fifo_rd_ptr];
assign wr_last = rsp_fifo_last[rsp_fifo_rd_ptr];

always @(posedge clk) begin
    if (!rst_n) begin
        busy <= 1'b0;
        done <= 1'b0;
        q_rw_valid <= 1'b0;
        q_rw_pair <= 2'd0;
        q_rw_addr <= 6'd0;
        req_count_reg <= 7'd0;
        rsp_count_reg <= 7'd0;
        outstanding_reg <= 2'd0;
        rsp_fifo_wr_ptr <= 2'd0;
        rsp_fifo_rd_ptr <= 2'd0;
        rsp_fifo_count <= 3'd0;
    end else begin
        done <= 1'b0;
        q_rw_valid <= 1'b0;
        if (start && !busy) begin
            busy <= 1'b1;
            req_count_reg <= 7'd0;
            rsp_count_reg <= 7'd0;
            outstanding_reg <= 2'd0;
            rsp_fifo_wr_ptr <= 2'd0;
            rsp_fifo_rd_ptr <= 2'd0;
            rsp_fifo_count <= 3'd0;
        end
        if (can_issue) begin
            q_rw_valid <= 1'b1;
            q_rw_pair <= req_count_reg[1:0];
            q_rw_addr <= {1'b0, page, req_count_reg[5:3], req_count_reg[2]};
            req_count_reg <= req_count_reg + 7'd1;
        end

        // SRAM read response is a single-cycle pulse with no ready;
        // buffer into small FIFO to avoid data loss when AXI W channel
        // withdraws ready during burst/B-response gaps.
        if (rsp_push) begin
            rsp_fifo_data[rsp_fifo_wr_ptr] <= q_rw_rdata;
            rsp_fifo_last[rsp_fifo_wr_ptr] <= (rsp_count_reg == 7'd63);
            rsp_fifo_wr_ptr <= rsp_fifo_wr_ptr + 2'd1;
            rsp_count_reg <= rsp_count_reg + 7'd1;
        end

        if (out_fire) begin
            rsp_fifo_rd_ptr <= rsp_fifo_rd_ptr + 2'd1;
        end

        case ({rsp_push, out_fire})
            2'b10: rsp_fifo_count <= rsp_fifo_count + 3'd1;
            2'b01: rsp_fifo_count <= rsp_fifo_count - 3'd1;
            default: rsp_fifo_count <= rsp_fifo_count;
        endcase

        case ({can_issue, rsp_push})
            2'b10: outstanding_reg <= outstanding_reg + 2'd1;
            2'b01: outstanding_reg <= outstanding_reg - 2'd1;
            default: outstanding_reg <= outstanding_reg;
        endcase
        if (out_fire && wr_last) begin
            busy <= 1'b0;
            done <= 1'b1;
        end

`ifndef SYNTHESIS
        if (rsp_push && (rsp_fifo_count == RSP_FIFO_DEPTH_VALUE[2:0]) && !out_fire) begin
            $display("ERROR: o_store_adapter response FIFO overflow");
            $finish;
        end
`endif
    end
end

endmodule

`default_nettype wire
