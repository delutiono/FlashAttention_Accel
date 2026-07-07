`timescale 1ns/1ps
`default_nettype none

// AXI4-Stream to internal DMA interface bridge.
// When stream_en=1: routes stream data directly to load/store adapters,
// bypassing DMA engine. Generates dma_done signals for page_manager.
module axi_stream_data_adapter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         stream_en,

    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [127:0] s_axis_tdata,
    input  wire [15:0]  s_axis_tkeep,
    input  wire [1:0]   s_axis_tuser,
    input  wire         s_axis_tlast,

    output reg          m_axis_tvalid,
    input  wire         m_axis_tready,
    output reg  [127:0] m_axis_tdata,
    output reg  [15:0]  m_axis_tkeep,
    output reg          m_axis_tlast,

    // Internal DMA rd interface
    output wire         rd_valid,
    input  wire         rd_ready,
    output wire [1:0]   rd_kind,
    output wire         rd_page,
    output wire [127:0] rd_data,
    output wire         rd_last,
    output wire [7:0]   rd_tag,

    // Internal DMA wr interface
    input  wire         wr_valid,
    output wire         wr_ready,
    input  wire [127:0] wr_data,
    input  wire [15:0]  wr_strb,
    input  wire         wr_last,

    // Page manager command interface
    input  wire         pm_cmd_valid,
    input  wire [1:0]   pm_cmd_kind,
    input  wire         pm_cmd_page,
    input  wire [7:0]   pm_cmd_tag,

    // Done signals
    output reg          done_valid,
    output reg  [1:0]   done_kind,
    output reg          done_page,
    output reg  [7:0]   done_tag,
    output reg          done_error
);

reg [1:0]  active_kind;
reg        active_page;
reg [7:0]  active_tag;
reg        active;
reg        o_active;

assign s_axis_tready = stream_en && active && rd_ready;

assign rd_valid = stream_en ? (s_axis_tvalid && active) : 1'b0;
assign rd_kind  = stream_en ? s_axis_tuser : 2'd0;
assign rd_page  = stream_en ? active_page : 1'b0;
assign rd_data  = s_axis_tdata;
assign rd_last  = s_axis_tlast;
assign rd_tag   = stream_en ? active_tag : 8'd0;

assign wr_ready = stream_en ? (o_active ? m_axis_tready : 1'b0) : 1'b0;

always @(posedge clk) begin
    if (!rst_n) begin
        active <= 1'b0;
        active_kind <= 2'd0;
        active_page <= 1'b0;
        active_tag <= 8'd0;
        o_active <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tdata <= 128'd0;
        m_axis_tkeep <= 16'd0;
        m_axis_tlast <= 1'b0;
        done_valid <= 1'b0;
        done_kind <= 2'd0;
        done_page <= 1'b0;
        done_tag <= 8'd0;
        done_error <= 1'b0;
    end else begin
        done_valid <= 1'b0;

        if (stream_en) begin
            if (pm_cmd_valid && !active && !o_active) begin
                if (pm_cmd_kind == 2'd3) begin
                    o_active <= 1'b1;
                end else begin
                    active <= 1'b1;
                    active_kind <= pm_cmd_kind;
                    active_page <= pm_cmd_page;
                    active_tag <= pm_cmd_tag;
                end
            end

            if (active && s_axis_tvalid && rd_ready && s_axis_tlast) begin
                active <= 1'b0;
                done_valid <= 1'b1;
                done_kind <= active_kind;
                done_page <= active_page;
                done_tag <= active_tag;
                done_error <= 1'b0;
            end

            if (o_active && wr_valid && m_axis_tready) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= wr_data;
                m_axis_tkeep  <= wr_strb;
                m_axis_tlast  <= wr_last;
                if (wr_last) begin
                    o_active <= 1'b0;
                    done_valid <= 1'b1;
                    done_kind <= 2'd3;
                    done_page <= 1'b0;
                    done_tag <= 8'hff;
                    done_error <= 1'b0;
                end
            end else if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
        end
    end
end

endmodule

`default_nettype wire
