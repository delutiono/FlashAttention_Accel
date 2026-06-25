`timescale 1ns/1ps

module fa_dma_wr (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        cmd_valid,
  output logic        cmd_ready,
  input  logic [63:0] cmd_addr,
  input  logic [8:0]  cmd_beats,

  input  logic [63:0] in_data,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic        in_last,

  output logic        done,
  output logic        error,
  output logic [31:0] byte_count,

  output logic [63:0] m_axi_awaddr,
  output logic [7:0]  m_axi_awlen,
  output logic [2:0]  m_axi_awsize,
  output logic [1:0]  m_axi_awburst,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,

  output logic [63:0] m_axi_wdata,
  output logic [7:0]  m_axi_wstrb,
  output logic        m_axi_wlast,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,

  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready
);
  logic       active;
  logic       aw_done;
  logic [8:0] beats_q;
  logic [8:0] in_count;
  logic [8:0] w_count;
  logic       wbuf_valid;
  logic [63:0] wbuf_data;
  logic       wbuf_last;

  assign cmd_ready     = !active;
  assign in_ready      = active && (in_count < beats_q) && !wbuf_valid;
  assign m_axi_awsize  = 3'd3;
  assign m_axi_awburst = 2'b01;
  assign m_axi_wdata   = wbuf_data;
  assign m_axi_wstrb   = 8'hff;
  assign m_axi_wlast   = wbuf_last;
  assign m_axi_wvalid  = wbuf_valid;
  assign m_axi_bready  = active && aw_done &&
                         (w_count == beats_q) && !wbuf_valid &&
                         m_axi_bvalid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active        <= 1'b0;
      aw_done       <= 1'b0;
      beats_q       <= '0;
      in_count      <= '0;
      w_count       <= '0;
      wbuf_valid    <= 1'b0;
      wbuf_data     <= '0;
      wbuf_last     <= 1'b0;
      done          <= 1'b0;
      error         <= 1'b0;
      byte_count    <= '0;
      m_axi_awaddr  <= '0;
      m_axi_awlen   <= '0;
      m_axi_awvalid <= 1'b0;
    end else begin
      done <= 1'b0;

      if (cmd_valid && cmd_ready) begin
        error      <= 1'b0;
        byte_count <= '0;
        in_count   <= '0;
        w_count    <= '0;
        wbuf_valid <= 1'b0;
        aw_done    <= 1'b0;
        beats_q    <= cmd_beats;

        if ((cmd_beats == 9'd0) || (cmd_beats > 9'd256)) begin
          active        <= 1'b0;
          m_axi_awvalid <= 1'b0;
          done          <= 1'b1;
          error         <= 1'b1;
        end else begin
          active        <= 1'b1;
          m_axi_awaddr  <= cmd_addr;
          m_axi_awlen   <= cmd_beats[7:0] - 8'd1;
          m_axi_awvalid <= 1'b1;
        end
      end

      if (m_axi_awvalid && m_axi_awready) begin
        m_axi_awvalid <= 1'b0;
        aw_done       <= 1'b1;
      end

      if (in_valid && in_ready) begin
        wbuf_valid <= 1'b1;
        wbuf_data  <= in_data;
        wbuf_last  <= (in_count == beats_q - 9'd1);
        in_count   <= in_count + 9'd1;
        if (in_last != (in_count == beats_q - 9'd1)) begin
          error <= 1'b1;
        end
      end

      if (m_axi_wvalid && m_axi_wready) begin
        wbuf_valid <= 1'b0;
        w_count    <= w_count + 9'd1;
        byte_count <= byte_count + 32'd8;
      end

      if (m_axi_bvalid && m_axi_bready) begin
        active  <= 1'b0;
        aw_done <= 1'b0;
        done    <= 1'b1;
        if (m_axi_bresp != 2'b00) begin
          error <= 1'b1;
        end
      end
    end
  end
endmodule
