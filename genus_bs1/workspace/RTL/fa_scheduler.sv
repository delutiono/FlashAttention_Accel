`timescale 1ns/1ps

import fa_pkg::*;

module fa_scheduler #(
  parameter int unsigned S_PARAM = FA_S,
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
  output logic [7:0]  kv_tile_o,
  output logic [7:0]  k_index_o,
  output logic        score_valid_o
);
  localparam int unsigned Q_BLOCKS = S_PARAM / BQ;
  localparam int unsigned KV_TILES = (S_PARAM + BK - 1) / BK;

  fa_state_e state_q;
  logic [7:0] q_index_q;
  logic [7:0] kv_tile_q;
  logic [7:0] k_offset_q;
  logic [15:0] k_index_w;
  logic       last_k_in_tile_w;
  logic       last_kv_tile_w;

  assign k_index_w = (16'(kv_tile_q) * 16'(BK)) + 16'(k_offset_q);
  assign last_k_in_tile_w = (16'(k_offset_q) == 16'(BK - 1)) ||
                            (k_index_w == 16'(S_PARAM - 1));
  assign last_kv_tile_w = (16'(kv_tile_q) == 16'(KV_TILES - 1));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q   <= FA_ST_IDLE;
      q_index_q <= 8'h0;
      kv_tile_q <= 8'h0;
      k_offset_q <= 8'h0;
      busy_o    <= 1'b0;
      done_o    <= 1'b0;
      error_o   <= 1'b0;
      cycles_o  <= 32'h0;
    end else if (soft_reset_i) begin
      state_q   <= FA_ST_IDLE;
      q_index_q <= 8'h0;
      kv_tile_q <= 8'h0;
      k_offset_q <= 8'h0;
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
            k_offset_q <= 8'h0;
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
          k_offset_q <= 8'h0;
          state_q   <= FA_ST_LOAD_KV;
        end
        FA_ST_LOAD_KV: begin
          k_offset_q <= 8'h0;
          state_q <= FA_ST_COMPUTE_TILE;
        end
        FA_ST_COMPUTE_TILE: begin
          if (last_k_in_tile_w) begin
            if (last_kv_tile_w) begin
              state_q <= FA_ST_FINALIZE;
            end else begin
              kv_tile_q <= kv_tile_q + 8'd1;
              state_q   <= FA_ST_LOAD_KV;
            end
          end else begin
            k_offset_q <= k_offset_q + 8'd1;
          end
        end
        FA_ST_FINALIZE: begin
          state_q <= FA_ST_WRITE_O;
        end
        FA_ST_WRITE_O: begin
          if (16'(q_index_q) == 16'(Q_BLOCKS - 1)) begin
            state_q <= FA_ST_DONE;
          end else begin
            q_index_q <= q_index_q + 8'd1;
            kv_tile_q <= 8'h0;
            k_offset_q <= 8'h0;
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
  assign k_index_o  = k_index_w[7:0];
  assign score_valid_o = (state_q == FA_ST_COMPUTE_TILE) &&
                         (k_index_w < 16'(S_PARAM)) &&
                         (!causal_en_i || (k_index_w <= 16'(q_index_q)));

  // Keep configuration inputs visible to lint until the real scheduler uses them.
  logic unused_cfg;
  assign unused_cfg = causal_en_i ^ q_base_i[0] ^ k_base_i[0] ^ v_base_i[0] ^
                      o_base_i[0] ^ neg_large_i[0] ^ scale_i[0];
endmodule
