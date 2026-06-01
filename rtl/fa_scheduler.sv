`timescale 1ns/1ps

import fa_pkg::*;

module fa_scheduler (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start_i,
  input  logic        soft_reset_i,
  input  logic        causal_en_i,
  input  logic [63:0] q_base_i,
  input  logic [63:0] k_base_i,
  input  logic [63:0] v_base_i,
  input  logic [63:0] o_base_i,
  input  logic [31:0] stride_bytes_i,
  input  logic [15:0] neg_large_i,
  input  logic [15:0] scale_i,
  output logic        busy_o,
  output logic        done_o,
  output logic        error_o,
  output logic [31:0] cycles_o
);
  fa_state_e state_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q  <= FA_ST_IDLE;
      busy_o   <= 1'b0;
      done_o   <= 1'b0;
      error_o  <= 1'b0;
      cycles_o <= 32'h0;
    end else if (soft_reset_i) begin
      state_q  <= FA_ST_IDLE;
      busy_o   <= 1'b0;
      done_o   <= 1'b0;
      error_o  <= 1'b0;
      cycles_o <= 32'h0;
    end else begin
      if (busy_o) begin
        cycles_o <= cycles_o + 32'd1;
      end

      unique case (state_q)
        FA_ST_IDLE: begin
          busy_o <= 1'b0;
          if (start_i) begin
            state_q  <= FA_ST_CHECK_CFG;
            busy_o   <= 1'b1;
            done_o   <= 1'b0;
            error_o  <= 1'b0;
            cycles_o <= 32'h0;
          end
        end
        FA_ST_CHECK_CFG: begin
          if (stride_bytes_i == 32'h0) begin
            state_q <= FA_ST_ERROR;
          end else begin
            state_q <= FA_ST_DONE;
          end
        end
        FA_ST_DONE: begin
          busy_o  <= 1'b0;
          done_o  <= 1'b1;
          state_q <= FA_ST_IDLE;
        end
        FA_ST_ERROR: begin
          busy_o  <= 1'b0;
          error_o <= 1'b1;
          state_q <= FA_ST_IDLE;
        end
        default: begin
          state_q <= FA_ST_ERROR;
        end
      endcase
    end
  end

  // Keep configuration inputs visible to lint until the real scheduler uses them.
  logic unused_cfg;
  assign unused_cfg = causal_en_i ^ q_base_i[0] ^ k_base_i[0] ^ v_base_i[0] ^
                      o_base_i[0] ^ neg_large_i[0] ^ scale_i[0];
endmodule
