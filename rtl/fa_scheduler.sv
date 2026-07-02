`timescale 1ns/1ps

import fa_pkg::*;

module fa_scheduler #(
  parameter int unsigned S_PARAM = FA_S,
  parameter int unsigned BQ = FA_Q_GROUP_ROWS,
  parameter int unsigned BK = FA_KV_TILE_ROWS
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
  output logic        score_valid_o,
  output logic [4:0]  q_group_o,
  output logic [2:0]  q_context_o,
  output logic [2:0]  kv_row_o,
  output logic        score_last_o,
  output logic        tile_done_o,
  output logic        group_done_o
);
  localparam int unsigned Q_GROUPS = (S_PARAM + BQ - 1) / BQ;
  localparam int unsigned GROUP_W = (Q_GROUPS <= 1) ? 1 : $clog2(Q_GROUPS);
  localparam int unsigned Q_CONTEXT_W = (BQ <= 1) ? 1 : $clog2(BQ);
  localparam int unsigned KV_ROW_W = (BK <= 1) ? 1 : $clog2(BK);

  fa_state_e state_q;
  logic [GROUP_W-1:0] q_group_q;
  logic [GROUP_W-1:0] kv_tile_q;
  logic [Q_CONTEXT_W-1:0] q_context_q;
  logic [KV_ROW_W-1:0] kv_row_q;
  logic [15:0] global_q_row_w;
  logic [15:0] global_k_row_w;
  logic [15:0] group_last_q_row_w;
  logic [15:0] group_last_kv_tile_w;
  logic        legal_score_w;
  logic        score_last_w;
  logic        last_context_w;
  logic        last_kv_row_w;
  logic        last_tile_w;
  logic        last_group_w;

  assign global_q_row_w = (16'(q_group_q) * 16'(BQ)) + 16'(q_context_q);
  assign global_k_row_w = (16'(kv_tile_q) * 16'(BK)) + 16'(kv_row_q);
  assign group_last_q_row_w =
      (((16'(q_group_q) + 16'd1) * 16'(BQ)) > 16'(S_PARAM)) ?
      16'(S_PARAM - 1) : (((16'(q_group_q) + 16'd1) * 16'(BQ)) - 16'd1);
  assign group_last_kv_tile_w = group_last_q_row_w / 16'(BK);
  assign legal_score_w = (global_q_row_w < 16'(S_PARAM)) &&
                         (global_k_row_w < 16'(S_PARAM)) &&
                         (!causal_en_i || (global_k_row_w <= global_q_row_w));
  assign score_last_w = legal_score_w && (global_k_row_w == global_q_row_w);
  assign last_context_w = (16'(q_context_q) == 16'(BQ - 1)) ||
                          (global_q_row_w == 16'(S_PARAM - 1));
  assign last_kv_row_w = (16'(kv_row_q) == 16'(BK - 1)) ||
                         (global_k_row_w == 16'(S_PARAM - 1));
  assign last_tile_w = (16'(kv_tile_q) == group_last_kv_tile_w);
  assign last_group_w = (16'(q_group_q) == 16'(Q_GROUPS - 1));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q   <= FA_ST_IDLE;
      q_group_q <= '0;
      kv_tile_q <= '0;
      q_context_q <= '0;
      kv_row_q <= '0;
      busy_o    <= 1'b0;
      done_o    <= 1'b0;
      error_o   <= 1'b0;
      cycles_o  <= 32'h0;
    end else if (soft_reset_i) begin
      state_q   <= FA_ST_IDLE;
      q_group_q <= '0;
      kv_tile_q <= '0;
      q_context_q <= '0;
      kv_row_q <= '0;
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
            q_group_q <= '0;
            kv_tile_q <= '0;
            q_context_q <= '0;
            kv_row_q <= '0;
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
          kv_tile_q <= '0;
          kv_row_q <= '0;
          q_context_q <= '0;
          state_q   <= FA_ST_LOAD_KV;
        end
        FA_ST_LOAD_KV: begin
          kv_row_q <= '0;
          q_context_q <= '0;
          state_q <= FA_ST_COMPUTE_TILE;
        end
        FA_ST_COMPUTE_TILE: begin
          if (last_context_w) begin
            q_context_q <= '0;
            if (last_kv_row_w) begin
              kv_row_q <= '0;
              if (last_tile_w) begin
                state_q <= FA_ST_FINALIZE;
              end else begin
                kv_tile_q <= kv_tile_q + 1'b1;
                state_q   <= FA_ST_LOAD_KV;
              end
            end else begin
              kv_row_q <= kv_row_q + 1'b1;
            end
          end else begin
            q_context_q <= q_context_q + 1'b1;
          end
        end
        FA_ST_FINALIZE: begin
          state_q <= FA_ST_WRITE_O;
        end
        FA_ST_WRITE_O: begin
          if (last_group_w) begin
            state_q <= FA_ST_DONE;
          end else begin
            q_group_q <= q_group_q + 1'b1;
            kv_tile_q <= '0;
            kv_row_q <= '0;
            q_context_q <= '0;
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
  assign q_group_o = 5'(q_group_q);
  assign kv_tile_o = 8'(kv_tile_q);
  assign q_context_o = 3'(q_context_q);
  assign kv_row_o = 3'(kv_row_q);
  assign q_index_o = global_q_row_w[7:0];
  assign k_index_o = global_k_row_w[7:0];
  assign score_valid_o = (state_q == FA_ST_COMPUTE_TILE) && legal_score_w;
  assign score_last_o = (state_q == FA_ST_COMPUTE_TILE) && score_last_w;
  assign tile_done_o = (state_q == FA_ST_COMPUTE_TILE) && last_context_w && last_kv_row_w;
  assign group_done_o = tile_done_o && last_tile_w;

  // Keep configuration inputs visible to lint until DMA address generation moves here.
  logic unused_cfg;
  assign unused_cfg = q_base_i[0] ^ k_base_i[0] ^ v_base_i[0] ^
                      o_base_i[0] ^ neg_large_i[0] ^ scale_i[0];
endmodule
