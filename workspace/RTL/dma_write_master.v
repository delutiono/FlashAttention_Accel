`timescale 1ns/1ps
`default_nettype none

module dma_write_master #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 128,
    parameter TAG_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  cmd_valid,
    output wire                  cmd_ready,
    input  wire [ADDR_WIDTH-1:0] cmd_base_addr,
    input  wire [15:0]           cmd_bytes,
    input  wire [TAG_WIDTH-1:0]  cmd_tag,
    input  wire                  wr_valid,
    output wire                  wr_ready,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire [(DATA_WIDTH/8)-1:0] wr_strb,
    input  wire                  wr_last,
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,
    output reg [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output reg [7:0]             m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [(DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,
    output reg                   done_valid,
    output reg [TAG_WIDTH-1:0]   done_tag,
    output reg                   error
);

localparam [1:0] ST_IDLE = 2'd0;
localparam [1:0] ST_AW   = 2'd1;
localparam [1:0] ST_W    = 2'd2;
localparam [1:0] ST_B    = 2'd3;

reg [1:0] state_reg;
reg [15:0] beats_left_reg;
// AXI burst 最多 16 beats：长度需要 5 bit，burst 内索引只需 4 bit。
reg [4:0] burst_beats_reg;
reg [3:0] beat_in_burst_reg;
reg [ADDR_WIDTH-1:0] addr_reg;
reg [TAG_WIDTH-1:0] tag_reg;

wire [15:0] cmd_beats = {4'd0, cmd_bytes[15:4]};
wire [ADDR_WIDTH-1:0] next_addr =
    addr_reg + ({{(ADDR_WIDTH-5){1'b0}}, burst_beats_reg} << 4);

// AXI4 INCR burst 既不能超过 16 beats，也不能跨越 4KB 边界。
function [4:0] select_burst_beats;
    input [ADDR_WIDTH-1:0] address;
    input [15:0] remaining_beats;
    reg [8:0] beats_to_4kb;
    reg [15:0] bounded_beats;
    begin
        beats_to_4kb = (address[11:0] == 12'd0) ? 9'd256 :
                       ((13'd4096 - {1'b0, address[11:0]}) >> 4);
        bounded_beats = (remaining_beats < beats_to_4kb) ?
                        remaining_beats : beats_to_4kb;
        select_burst_beats = (bounded_beats > 16) ? 5'd16 :
                             bounded_beats[4:0];
    end
endfunction

assign cmd_ready = (state_reg == ST_IDLE);
assign m_axi_awsize = 3'd4;
assign m_axi_awburst = 2'b01;
assign wr_ready = (state_reg == ST_W) && m_axi_wready;
assign m_axi_wvalid = (state_reg == ST_W) && wr_valid;
assign m_axi_wdata = wr_data;
assign m_axi_wstrb = wr_strb;
assign m_axi_wlast = ({1'b0, beat_in_burst_reg} == burst_beats_reg - 5'd1);
assign m_axi_bready = (state_reg == ST_B);

always @(posedge clk) begin
    if (!rst_n) begin
        state_reg <= ST_IDLE;
        m_axi_awvalid <= 1'b0;
        m_axi_awaddr <= {ADDR_WIDTH{1'b0}};
        m_axi_awlen <= 8'd0;
        beats_left_reg <= 16'd0;
        burst_beats_reg <= 5'd0;
        beat_in_burst_reg <= 4'd0;
        addr_reg <= {ADDR_WIDTH{1'b0}};
        tag_reg <= {TAG_WIDTH{1'b0}};
        done_valid <= 1'b0;
        done_tag <= {TAG_WIDTH{1'b0}};
        error <= 1'b0;
    end else begin
        done_valid <= 1'b0;
        case (state_reg)
            ST_IDLE: begin
                if (cmd_valid) begin
                    addr_reg <= cmd_base_addr;
                    beats_left_reg <= cmd_beats;
                    burst_beats_reg <= select_burst_beats(cmd_base_addr, cmd_beats);
                    tag_reg <= cmd_tag;
                    state_reg <= ST_AW;
                end
            end
            ST_AW: begin
                // 地址阶段持续清零，确保进入 ST_W 前计数器是确定值。
                beat_in_burst_reg <= 4'd0;
                m_axi_awvalid <= 1'b1;
                m_axi_awaddr <= addr_reg;
                m_axi_awlen <= {3'd0, burst_beats_reg} - 8'd1;
                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    state_reg <= ST_W;
                end
            end
            ST_W: begin
                if (wr_valid && m_axi_wready) begin
                    beat_in_burst_reg <= beat_in_burst_reg + 4'd1;
                    beats_left_reg <= beats_left_reg - 16'd1;
                    if (m_axi_wlast) begin
                        state_reg <= ST_B;
                    end
`ifndef SYNTHESIS
                    if (wr_last && (beats_left_reg != 16'd1)) begin
                        $display("ERROR: dma_write_master early wr_last");
                        $finish;
                    end
`endif
                end
            end
            ST_B: begin
                if (m_axi_bvalid) begin
                    if (m_axi_bresp != 2'b00)
                        error <= 1'b1;
                    addr_reg <= next_addr;
                    if (beats_left_reg == 16'd0) begin
                        done_valid <= 1'b1;
                        done_tag <= tag_reg;
                        state_reg <= ST_IDLE;
                    end else begin
                        burst_beats_reg <= select_burst_beats(next_addr, beats_left_reg);
                        state_reg <= ST_AW;
                    end
                end
            end
            default: state_reg <= ST_IDLE;
        endcase
    end
end

endmodule

`default_nettype wire
