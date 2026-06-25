`timescale 1ns/1ps

import fa_pkg::*;

module fa_regfile (
  input  logic         clk,
  input  logic         rst_n,

  input  logic [11:0]  s_axil_awaddr,
  input  logic         s_axil_awvalid,
  output logic         s_axil_awready,
  input  logic [31:0]  s_axil_wdata,
  input  logic [3:0]   s_axil_wstrb,
  input  logic         s_axil_wvalid,
  output logic         s_axil_wready,
  output logic [1:0]   s_axil_bresp,
  output logic         s_axil_bvalid,
  input  logic         s_axil_bready,
  input  logic [11:0]  s_axil_araddr,
  input  logic         s_axil_arvalid,
  output logic         s_axil_arready,
  output logic [31:0]  s_axil_rdata,
  output logic [1:0]   s_axil_rresp,
  output logic         s_axil_rvalid,
  input  logic         s_axil_rready,

  output logic         start_pulse,
  output logic         soft_reset_pulse,
  output logic         done_clear_pulse,
  output logic         irq_en,
  output logic         causal_en,
  output logic [63:0]  q_base,
  output logic [63:0]  k_base,
  output logic [63:0]  v_base,
  output logic [63:0]  o_base,
  output logic [31:0]  stride_bytes,
  output logic [15:0]  neg_large,
  output logic [15:0]  scale,

  input  logic [31:0]  cycles_i,
  input  logic         busy_i,
  input  logic         done_i,
  input  logic         error_i
);
  logic        aw_pending;
  logic [11:0] awaddr_q;
  logic        w_pending;
  logic [31:0] wdata_q;
  logic [3:0]  wstrb_q;
  logic        aw_take;
  logic        w_take;
  logic        write_fire;
  logic [11:0] write_addr;
  logic [31:0] write_data;
  logic [3:0]  write_strb;
  logic read_fire;

  function automatic logic [31:0] apply_wstrb(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0]  strobe
  );
    logic [31:0] merged;
    begin
      merged = old_value;
      if (strobe[0]) merged[7:0]   = new_value[7:0];
      if (strobe[1]) merged[15:8]  = new_value[15:8];
      if (strobe[2]) merged[23:16] = new_value[23:16];
      if (strobe[3]) merged[31:24] = new_value[31:24];
      return merged;
    end
  endfunction

  assign aw_take    = s_axil_awvalid & s_axil_awready;
  assign w_take     = s_axil_wvalid & s_axil_wready;
  assign write_fire = !s_axil_bvalid
                    & (aw_pending | aw_take)
                    & (w_pending | w_take);
  assign write_addr = aw_pending ? awaddr_q : s_axil_awaddr;
  assign write_data = w_pending ? wdata_q : s_axil_wdata;
  assign write_strb = w_pending ? wstrb_q : s_axil_wstrb;
  assign read_fire  = s_axil_arvalid & s_axil_arready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_bvalid    <= 1'b0;
      s_axil_bresp     <= 2'b00;
      aw_pending       <= 1'b0;
      awaddr_q         <= 12'h000;
      w_pending        <= 1'b0;
      wdata_q          <= 32'h0000_0000;
      wstrb_q          <= 4'h0;
      s_axil_rvalid    <= 1'b0;
      s_axil_rresp     <= 2'b00;
      s_axil_rdata     <= 32'h0;
      start_pulse      <= 1'b0;
      soft_reset_pulse <= 1'b0;
      done_clear_pulse <= 1'b0;
      irq_en           <= 1'b0;
      causal_en        <= 1'b1;
      q_base           <= 64'h0;
      k_base           <= 64'h0;
      v_base           <= 64'h0;
      o_base           <= 64'h0;
      stride_bytes     <= FA_STRIDE_DEFAULT[31:0];
      neg_large        <= 16'h8000;
      scale            <= 16'd32;
    end else begin
      start_pulse      <= 1'b0;
      soft_reset_pulse <= 1'b0;
      done_clear_pulse <= 1'b0;

      if (s_axil_bvalid & s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      if (s_axil_rvalid & s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end

      if (write_fire) begin
        aw_pending <= 1'b0;
        w_pending  <= 1'b0;
      end else begin
        if (aw_take) begin
          aw_pending <= 1'b1;
          awaddr_q   <= s_axil_awaddr;
        end
        if (w_take) begin
          w_pending <= 1'b1;
          wdata_q   <= s_axil_wdata;
          wstrb_q   <= s_axil_wstrb;
        end
      end

      if (write_fire) begin
        s_axil_bvalid <= 1'b1;
        unique case (write_addr)
          REG_CTRL: begin
            if (write_strb[0]) begin
              start_pulse      <= write_data[0];
              soft_reset_pulse <= write_data[1];
              irq_en           <= write_data[2];
            end
          end
          REG_STATUS: begin
            if (write_strb[0] && write_data[1]) begin
              done_clear_pulse <= 1'b1;
            end
          end
          REG_CFG: begin
            if (write_strb[0]) causal_en <= write_data[0];
          end
          REG_Q_BASE_L:     q_base[31:0]  <= apply_wstrb(q_base[31:0], write_data, write_strb);
          REG_Q_BASE_H:     q_base[63:32] <= apply_wstrb(q_base[63:32], write_data, write_strb);
          REG_K_BASE_L:     k_base[31:0]  <= apply_wstrb(k_base[31:0], write_data, write_strb);
          REG_K_BASE_H:     k_base[63:32] <= apply_wstrb(k_base[63:32], write_data, write_strb);
          REG_V_BASE_L:     v_base[31:0]  <= apply_wstrb(v_base[31:0], write_data, write_strb);
          REG_V_BASE_H:     v_base[63:32] <= apply_wstrb(v_base[63:32], write_data, write_strb);
          REG_O_BASE_L:     o_base[31:0]  <= apply_wstrb(o_base[31:0], write_data, write_strb);
          REG_O_BASE_H:     o_base[63:32] <= apply_wstrb(o_base[63:32], write_data, write_strb);
          REG_STRIDE_BYTES: stride_bytes  <= apply_wstrb(stride_bytes, write_data, write_strb);
          REG_NEG_LARGE: begin
            neg_large <= apply_wstrb({16'h0, neg_large}, write_data, write_strb)[15:0];
          end
          REG_SCALE: begin
            scale <= apply_wstrb({16'h0, scale}, write_data, write_strb)[15:0];
          end
          default: begin
          end
        endcase
      end

      if (read_fire) begin
        s_axil_rvalid <= 1'b1;
        unique case (s_axil_araddr)
          REG_CTRL:         s_axil_rdata <= {29'h0, irq_en, 2'b00};
          REG_STATUS:       s_axil_rdata <= {29'h0, error_i, done_i, busy_i};
          REG_CFG:          s_axil_rdata <= {31'h0, causal_en};
          REG_Q_BASE_L:     s_axil_rdata <= q_base[31:0];
          REG_Q_BASE_H:     s_axil_rdata <= q_base[63:32];
          REG_K_BASE_L:     s_axil_rdata <= k_base[31:0];
          REG_K_BASE_H:     s_axil_rdata <= k_base[63:32];
          REG_V_BASE_L:     s_axil_rdata <= v_base[31:0];
          REG_V_BASE_H:     s_axil_rdata <= v_base[63:32];
          REG_O_BASE_L:     s_axil_rdata <= o_base[31:0];
          REG_O_BASE_H:     s_axil_rdata <= o_base[63:32];
          REG_STRIDE_BYTES: s_axil_rdata <= stride_bytes;
          REG_NEG_LARGE:    s_axil_rdata <= {16'h0, neg_large};
          REG_SCALE:        s_axil_rdata <= {16'h0, scale};
          REG_CYCLES:       s_axil_rdata <= cycles_i;
          default:          s_axil_rdata <= 32'h0;
        endcase
      end
    end
  end

  assign s_axil_awready = !s_axil_bvalid & !aw_pending;
  assign s_axil_wready  = !s_axil_bvalid & !w_pending;
  assign s_axil_arready = !s_axil_rvalid;
endmodule
