`timescale 1ns/1ps
`default_nettype none

module dma_read_master #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 128,
    parameter TAG_WIDTH = 8
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   cmd_valid,
    output wire                   cmd_ready,
    input  wire [ADDR_WIDTH-1:0]  cmd_base_addr,
    input  wire [15:0]            cmd_bytes,
    input  wire [1:0]             cmd_kind,
    input  wire                   cmd_page,
    input  wire [TAG_WIDTH-1:0]   cmd_tag,
    output reg                    m_axi_arvalid,
    input  wire                   m_axi_arready,
    output reg  [ADDR_WIDTH-1:0]  m_axi_araddr,
    output reg  [7:0]             m_axi_arlen,
    output wire [2:0]             m_axi_arsize,
    output wire [1:0]             m_axi_arburst,
    input  wire [DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready,
    output wire                   rd_valid,
    input  wire                   rd_ready,
    output wire [DATA_WIDTH-1:0]  rd_data,
    output wire                   rd_last,
    output wire [1:0]             rd_kind,
    output wire                   rd_page,
    output wire [TAG_WIDTH-1:0]   rd_tag,
    output reg                    done_valid,
    output reg  [1:0]             done_kind,
    output reg                    done_page,
    output reg  [TAG_WIDTH-1:0]   done_tag,
    output reg                    error
);

localparam [1:0] ST_IDLE = 2'd0;
localparam [1:0] ST_AR   = 2'd1;
localparam [1:0] ST_R    = 2'd2;
localparam [1:0] ST_DONE = 2'd3;

reg [1:0] state_reg;
reg [15:0] beats_left_reg;
reg [7:0] burst_beats_reg;
reg [7:0] beat_in_burst_reg;
reg [ADDR_WIDTH-1:0] addr_reg;
reg [1:0] kind_reg;
reg page_reg;
reg [TAG_WIDTH-1:0] tag_reg;

wire [15:0] cmd_beats = {4'd0, cmd_bytes[15:4]};
wire [11:0] bytes_to_4kb = 12'h000 - cmd_base_addr[11:0];
wire [8:0] beats_to_4kb = (cmd_base_addr[11:0] == 12'd0) ? 9'd256 : {1'b0, bytes_to_4kb[11:4]};
wire [8:0] max_burst_beats = (beats_to_4kb < 9'd16) ? beats_to_4kb : 9'd16;
wire [8:0] next_burst_beats = (cmd_beats < {7'd0, max_burst_beats}) ? {1'b0, cmd_beats[7:0]} : max_burst_beats;

assign cmd_ready = (state_reg == ST_IDLE);
assign m_axi_arsize = 3'd4;
assign m_axi_arburst = 2'b01;
assign m_axi_rready = rd_ready;
assign rd_valid = (state_reg == ST_R) && m_axi_rvalid;
assign rd_data = m_axi_rdata;
assign rd_last = (beats_left_reg == 16'd1) && m_axi_rvalid;
assign rd_kind = kind_reg;
assign rd_page = page_reg;
assign rd_tag = tag_reg;

always @(posedge clk) begin
    if (!rst_n) begin
        state_reg <= ST_IDLE;
        m_axi_arvalid <= 1'b0;
        m_axi_araddr <= {ADDR_WIDTH{1'b0}};
        m_axi_arlen <= 8'd0;
        beats_left_reg <= 16'd0;
        burst_beats_reg <= 8'd0;
        beat_in_burst_reg <= 8'd0;
        addr_reg <= {ADDR_WIDTH{1'b0}};
        kind_reg <= 2'd0;
        page_reg <= 1'b0;
        tag_reg <= {TAG_WIDTH{1'b0}};
        done_valid <= 1'b0;
        done_kind <= 2'd0;
        done_page <= 1'b0;
        done_tag <= {TAG_WIDTH{1'b0}};
        error <= 1'b0;
    end else begin
        done_valid <= 1'b0;
        case (state_reg)
            ST_IDLE: begin
                m_axi_arvalid <= 1'b0;
                if (cmd_valid) begin
                    addr_reg <= cmd_base_addr;
                    beats_left_reg <= cmd_beats;
                    burst_beats_reg <= next_burst_beats[7:0];
                    beat_in_burst_reg <= 8'd0;
                    kind_reg <= cmd_kind;
                    page_reg <= cmd_page;
                    tag_reg <= cmd_tag;
                    state_reg <= ST_AR;
                end
            end
            ST_AR: begin
                m_axi_arvalid <= 1'b1;
                m_axi_araddr <= addr_reg;
                m_axi_arlen <= burst_beats_reg - 8'd1;
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    beat_in_burst_reg <= 8'd0;
                    state_reg <= ST_R;
                end
            end
            ST_R: begin
                if (m_axi_rvalid && rd_ready) begin
                    if (m_axi_rresp != 2'b00)
                        error <= 1'b1;
                    beats_left_reg <= beats_left_reg - 16'd1;
                    beat_in_burst_reg <= beat_in_burst_reg + 8'd1;
                    if (m_axi_rlast || (beat_in_burst_reg == burst_beats_reg - 8'd1)) begin
                        addr_reg <= addr_reg + ({56'd0, burst_beats_reg} << 4);
                        if (beats_left_reg == 16'd1) begin
                            state_reg <= ST_DONE;
                        end else begin
                            burst_beats_reg <= ((beats_left_reg - 16'd1) > 16'd16) ? 8'd16 : (beats_left_reg[7:0] - 8'd1);
                            state_reg <= ST_AR;
                        end
                    end
                end
            end
            default: begin
                done_valid <= 1'b1;
                done_kind <= kind_reg;
                done_page <= page_reg;
                done_tag <= tag_reg;
                state_reg <= ST_IDLE;
            end
        endcase
    end
end

endmodule

`default_nettype wire
