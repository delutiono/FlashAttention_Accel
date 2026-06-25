`timescale 1ns/1ps

module fa_dma_rd (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        cmd_valid,
  output logic        cmd_ready,
  input  logic [63:0] cmd_addr,
  input  logic [8:0]  cmd_beats,

  output logic [63:0] out_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic        out_last,

  output logic        done,
  output logic        error,
  output logic [31:0] byte_count,

  output logic [63:0] m_axi_araddr,
  output logic [7:0]  m_axi_arlen,
  output logic [2:0]  m_axi_arsize,
  output logic [1:0]  m_axi_arburst,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,

  input  logic [63:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rlast,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready
);
  logic       active;
  logic       ar_done;
  logic [8:0] beats_q;
  logic [8:0] r_count;

  assign cmd_ready     = !active;
  assign m_axi_arsize  = 3'd3;
  assign m_axi_arburst = 2'b01;
  assign m_axi_rready  = active && ar_done &&
                         (r_count < beats_q) &&
                         (!out_valid || out_ready);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active        <= 1'b0;
      ar_done       <= 1'b0;
      beats_q       <= '0;
      r_count       <= '0;
      out_data      <= '0;
      out_valid     <= 1'b0;
      out_last      <= 1'b0;
      done          <= 1'b0;
      error         <= 1'b0;
      byte_count    <= '0;
      m_axi_araddr  <= '0;
      m_axi_arlen   <= '0;
      m_axi_arvalid <= 1'b0;
    end else begin
      done <= 1'b0;

      if (cmd_valid && cmd_ready) begin
        error      <= 1'b0;
        byte_count <= '0;
        r_count    <= '0;
        out_valid  <= 1'b0;
        out_last   <= 1'b0;
        ar_done    <= 1'b0;
        beats_q    <= cmd_beats;

        if ((cmd_beats == 9'd0) || (cmd_beats > 9'd256)) begin
          active        <= 1'b0;
          m_axi_arvalid <= 1'b0;
          done          <= 1'b1;
          error         <= 1'b1;
        end else begin
          active        <= 1'b1;
          m_axi_araddr  <= cmd_addr;
          m_axi_arlen   <= cmd_beats[7:0] - 8'd1;
          m_axi_arvalid <= 1'b1;
        end
      end

      if (m_axi_arvalid && m_axi_arready) begin
        m_axi_arvalid <= 1'b0;
        ar_done       <= 1'b1;
      end

      if (out_valid && out_ready) begin
        if (out_last) begin
          active    <= 1'b0;
          ar_done   <= 1'b0;
          done      <= 1'b1;
        end
        out_valid <= 1'b0;
      end

      if (m_axi_rvalid && m_axi_rready) begin
        out_data  <= m_axi_rdata;
        out_valid <= 1'b1;
        out_last  <= (r_count == beats_q - 9'd1);
        r_count   <= r_count + 9'd1;
        byte_count <= byte_count + 32'd8;

        if ((m_axi_rresp != 2'b00) ||
            (m_axi_rlast != (r_count == beats_q - 9'd1))) begin
          error <= 1'b1;
        end
      end
    end
  end
endmodule
