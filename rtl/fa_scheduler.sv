`timescale 1ns/1ps

import fa_pkg::*;

module fa_scheduler #(
  parameter int unsigned BQ = 1,
  parameter int unsigned BK = 32
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start_i,
  input  logic        soft_reset_i,
  input  logic        done_clear_i,
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
  output logic [31:0] cycles_o,
  output fa_state_e   state_o,
  output logic [7:0]  q_index_o,
  output logic [7:0]  kv_tile_o
);
  localparam int unsigned Q_BLOCKS = FA_S / BQ;
  localparam int unsigned KV_TILES = FA_S / BK;

  fa_state_e state_q;
  logic [7:0] q_index_q;
  logic [7:0] kv_tile_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q   <= FA_ST_IDLE;
      q_index_q <= 8'h0;
      kv_tile_q <= 8'h0;
      busy_o    <= 1'b0;
      done_o    <= 1'b0;
      error_o   <= 1'b0;
      cycles_o  <= 32'h0;
    end else if (soft_reset_i) begin
      state_q   <= FA_ST_IDLE;
      q_index_q <= 8'h0;
      kv_tile_q <= 8'h0;
      busy_o    <= 1'b0;
      done_o    <= 1'b0;
      error_o   <= 1'b0;
      cycles_o  <= 32'h0;
    end else begin
      if (done_clear_i) begin
        done_o <= 1'b0;
      end

      if (busy_o) begin
        cycles_o <= cycles_o + 32'd1;
      end

      unique case (state_q)
        FA_ST_IDLE: begin
          busy_o <= 1'b0;
          if (start_i) begin
            state_q   <= FA_ST_CHECK_CFG;
            q_index_q <= 8'h0;
            kv_tile_q <= 8'h0;
            busy_o    <= 1'b1;
            done_o    <= 1'b0;
            error_o   <= 1'b0;
            cycles_o  <= 32'h0;
          end
        end
        FA_ST_CHECK_CFG: begin
          if (stride_bytes_i == 32'h0) begin
            state_q <= FA_ST_ERROR;
          end else begin
            state_q <= FA_ST_LOAD_Q;
          end
        end
        FA_ST_LOAD_Q: begin
          state_q <= FA_ST_INIT_ROW;
        end
        FA_ST_INIT_ROW: begin
          kv_tile_q <= 8'h0;
          state_q   <= FA_ST_LOAD_KV;
        end
        FA_ST_LOAD_KV: begin
          state_q <= FA_ST_COMPUTE_TILE;
        end
        FA_ST_COMPUTE_TILE: begin
          if (kv_tile_q == KV_TILES[7:0] - 8'd1) begin
            state_q <= FA_ST_FINALIZE;
          end else begin
            kv_tile_q <= kv_tile_q + 8'd1;
            state_q   <= FA_ST_LOAD_KV;
          end
        end
        FA_ST_FINALIZE: begin
          state_q <= FA_ST_WRITE_O;
        end
        FA_ST_WRITE_O: begin
          if (q_index_q == Q_BLOCKS[7:0] - 8'd1) begin
            state_q <= FA_ST_DONE;
          end else begin
            q_index_q <= q_index_q + 8'd1;
            state_q   <= FA_ST_LOAD_Q;
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

  assign state_o    = state_q;
  assign q_index_o  = q_index_q;
  assign kv_tile_o  = kv_tile_q;

  // Keep configuration inputs visible to lint until the real scheduler uses them.
  logic unused_cfg;
  assign unused_cfg = causal_en_i ^ q_base_i[0] ^ k_base_i[0] ^ v_base_i[0] ^
                      o_base_i[0] ^ neg_large_i[0] ^ scale_i[0];
endmodule
