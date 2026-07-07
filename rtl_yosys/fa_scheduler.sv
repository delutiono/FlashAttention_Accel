`timescale 1ns/1ps

`include "fa_defines.vh"

module fa_scheduler #(
  parameter S         = 256,
  parameter D         = 64,
  parameter ELEM_W    = 16,
  parameter BK        = 32,
  parameter DOT_LANES = 32,
  parameter V_LANES   = 16,
  parameter SCORE_W   = 24,
  parameter EXP_W     = 16,
  parameter L_W       = 32,
  parameter ACC_W     = 48
) (
  input  logic         clk,
  input  logic         rst_n,

  input  logic         start_i,
  input  logic         soft_reset_i,
  input  logic         causal_en_i,

  input  logic signed [S*D*ELEM_W-1:0] q_data_i,
  input  logic signed [S*D*ELEM_W-1:0] k_data_i,
  input  logic signed [S*D*ELEM_W-1:0] v_data_i,
  input  logic [15:0]  neg_large_i,
  input  logic [15:0]  scale_i,

  output logic         busy_o,
  output logic         done_o,
  output logic         error_o,
  output logic [31:0]  cycles_o,
  output logic signed [S*D*ELEM_W-1:0] o_data_o,
  output logic signed [S*D*ELEM_W-1:0] o_flat_o
);

  localparam DOT_CHUNKS = D / DOT_LANES;
  localparam V_CHUNKS   = D / V_LANES;

  // --- counters ---
  logic [$clog2(S)-1:0]    q_row;
  logic [$clog2(S)-1:0]    tile_base;
  logic [$clog2(BK)-1:0]   k_off;
  logic [2:0]              v_chunk;
  logic [1:0]              sm_wait;

  // --- local Q/K/V buffers ---
  logic signed [ELEM_W-1:0] q_buf [D];
  logic signed [ELEM_W-1:0] k_buf [BK][D];
  logic signed [ELEM_W-1:0] v_buf [BK][D];

  // --- quant ---
  logic signed [95:0] quant_prod;

  // --- dot_pe ---
  logic               dot_valid_i, dot_clr_i, dot_valid_o;
  logic [2:0]         dot_chunk;
  logic signed [ELEM_W-1:0] q_chunk [DOT_LANES];
  logic signed [ELEM_W-1:0] k_chunk [DOT_LANES];
  logic signed [ACC_W-1:0] dot_result;

  // --- softmax ---
  logic               sm_row_start, sm_score_valid, sm_v_valid, sm_last_tile;
  logic               sm_ready;
  logic signed [SCORE_W-1:0] sm_score;
  logic signed [15:0] sm_v [V_LANES];
  logic [L_W-1:0]      sm_l;
  logic signed [D*ACC_W-1:0] sm_acc_flat;

  // --- recip ---
  logic         recip_req, recip_valid;
  logic [L_W-1:0] recip_inv_l;

  // --- score scaling ---
  logic signed [47:0] score_scaled;
  logic signed [SCORE_W-1:0] score_q;

  assign score_scaled = $signed(dot_result) * $signed({1'b0, scale_i});
  assign score_q      = SCORE_W'(score_scaled >>> 8);

  // =============================================================
  //  Sub-modules
  // =============================================================

  // Pack/unpack wrappers for dot_pe
  logic signed [ELEM_W*DOT_LANES-1:0] q_chunk_flat, k_chunk_flat;
  always_comb begin
    for (int i = 0; i < DOT_LANES; i++) begin
      q_chunk_flat[i*ELEM_W +: ELEM_W] = q_chunk[i];
      k_chunk_flat[i*ELEM_W +: ELEM_W] = k_chunk[i];
    end
  end

`ifdef GATE_SIM
  fa_dot_pe u_dot (
`else
  fa_dot_pe #(.D(D), .LANES(DOT_LANES), .ELEM_W(ELEM_W), .ACC_W(ACC_W)) u_dot (
`endif
    .clk(clk), .rst_n(rst_n),
    .valid_i(dot_valid_i), .acc_clr_i(dot_clr_i),
    .q_i(q_chunk_flat), .k_i(k_chunk_flat),
    .valid_o(dot_valid_o), .dot_o(dot_result)
  );

  // Pack/unpack wrapper for softmax V input
  logic signed [16*V_LANES-1:0] sm_v_flat;
  always_comb begin
    for (int i = 0; i < V_LANES; i++)
      sm_v_flat[i*16 +: 16] = sm_v[i];
  end

`ifdef GATE_SIM
  fa_softmax_online u_softmax (
`else
  fa_softmax_online #(.SCORE_W(SCORE_W), .EXP_W(EXP_W), .L_W(L_W),
                       .ACC_W(ACC_W), .V_ACC_LANES(V_LANES), .D(D)) u_softmax (
`endif
    .clk(clk), .rst_n(rst_n),
    .row_start_i(sm_row_start), .score_valid_i(sm_score_valid), .score_i(sm_score),
    .v_i(sm_v_flat), .v_valid_i(sm_v_valid), .last_tile_i(sm_last_tile),
    .ready_o(sm_ready), .l_o(sm_l), .acc_o(), .acc_o_flat(sm_acc_flat),
    .m_o(), .done_o(), .o_elem_o()
  );

  fa_recip_approx u_recip (
    .clk(clk), .rst_n(rst_n),
    .valid_i(recip_req), .x_i(sm_l),
    .valid_o(recip_valid), .y_o(recip_inv_l)
  );

  // =============================================================
  //  Main state machine — accesses packed ports directly via bit-slicing
  // =============================================================
  typedef enum logic [3:0] {
    ST_IDLE, ST_LOAD_Q, ST_INIT_ROW, ST_LOAD_KV,
    ST_DOT_CHUNK, ST_DOT_WAIT, ST_SOFTMAX, ST_VACC,
    ST_NEXT_K, ST_NEXT_TILE, ST_RECIP, ST_RECIP_WAIT,
    ST_QUANT, ST_NEXT_Q, ST_DONE
  } st_e;

  st_e st;
  logic [31:0] cycles;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st      <= ST_IDLE;
      busy_o  <= 1'b0;  done_o <= 1'b0;  error_o <= 1'b0;
      cycles  <= 32'h0;
      q_row   <= '0;  tile_base <= '0;  k_off <= '0;

      dot_valid_i <= 1'b0;  dot_clr_i <= 1'b0;  dot_chunk <= '0;
      sm_row_start <= 1'b0;  sm_score_valid <= 1'b0;
      sm_v_valid <= 1'b0;  sm_last_tile <= 1'b0;
      recip_req <= 1'b0;  v_chunk <= '0;  sm_wait <= '0;

      o_flat_o <= '0;

    end else if (soft_reset_i) begin
      st <= ST_IDLE;  busy_o <= 1'b0;  done_o <= 1'b0;

    end else begin
      if (busy_o) cycles <= cycles + 32'd1;

      dot_valid_i   <= 1'b0;
      dot_clr_i     <= 1'b0;
      sm_row_start  <= 1'b0;
      sm_score_valid <= 1'b0;
      sm_v_valid    <= 1'b0;
      sm_last_tile  <= 1'b0;
      recip_req     <= 1'b0;

      unique case (st)

        ST_IDLE: begin
          if (start_i) begin
            busy_o <= 1'b1;  done_o <= 1'b0;  cycles <= 32'h0;
            q_row <= '0;
            st    <= ST_LOAD_Q;
          end
        end

        ST_LOAD_Q: begin
          for (int d = 0; d < D; d++)
            q_buf[d] <= q_data_i[(q_row*D + d)*ELEM_W +: ELEM_W];
          st <= ST_INIT_ROW;
        end

        ST_INIT_ROW: begin
          sm_row_start <= 1'b1;
          tile_base <= '0;
          st <= ST_LOAD_KV;
        end

        ST_LOAD_KV: begin
          for (int k = 0; k < BK; k++)
            if ((tile_base + k) < S)
              for (int d = 0; d < D; d++) begin
                k_buf[k][d] <= k_data_i[((tile_base + k)*D + d)*ELEM_W +: ELEM_W];
                v_buf[k][d] <= v_data_i[((tile_base + k)*D + d)*ELEM_W +: ELEM_W];
              end
          k_off <= '0;
          st <= ST_DOT_CHUNK;
        end

        ST_DOT_CHUNK: begin
          if ((tile_base + k_off) >= S) begin
            st <= ST_NEXT_K;
          end else if (causal_en_i && ((tile_base + k_off) > q_row)) begin
            st <= ST_NEXT_K;
          end else begin
            dot_valid_i <= 1'b1;
            dot_clr_i   <= 1'b1;
            for (int d = 0; d < DOT_LANES; d++) begin
              q_chunk[d] <= q_buf[d];
              k_chunk[d] <= k_buf[k_off][d];
            end
            dot_chunk <= 3'd1;
            st <= ST_DOT_WAIT;
          end
        end

        ST_DOT_WAIT: begin
          if (dot_chunk < DOT_CHUNKS) begin
            dot_valid_i <= 1'b1;
            for (int d = 0; d < DOT_LANES; d++) begin
              q_chunk[d] <= q_buf[dot_chunk * DOT_LANES + d];
              k_chunk[d] <= k_buf[k_off][dot_chunk * DOT_LANES + d];
            end
            dot_chunk <= dot_chunk + 3'd1;
          end
          if (dot_valid_o && dot_chunk == DOT_CHUNKS) begin
            sm_score <= score_q;
            sm_score_valid <= 1'b1;
            sm_last_tile <= (tile_base + BK >= S);
            st <= ST_SOFTMAX;
          end
        end

        ST_SOFTMAX: begin
          if (sm_wait < 2'd2) begin
            sm_wait <= sm_wait + 2'd1;
          end else begin
            sm_v_valid <= 1'b1;
            for (int d = 0; d < V_LANES; d++)
              sm_v[d] <= v_buf[k_off][d];
            v_chunk <= 3'd1;
            sm_wait <= '0;
            st <= ST_VACC;
          end
        end

        ST_VACC: begin
          if (v_chunk < V_CHUNKS) begin
            sm_v_valid <= 1'b1;
            for (int d = 0; d < V_LANES; d++)
              sm_v[d] <= v_buf[k_off][v_chunk * V_LANES + d];
            v_chunk <= v_chunk + 3'd1;
          end else if (sm_ready) begin
            st <= ST_NEXT_K;
          end
        end

        ST_NEXT_K: begin
          if (k_off == BK - 1 || (tile_base + k_off + 1) >= S)
            st <= ST_NEXT_TILE;
          else begin
            k_off <= k_off + 1'b1;
            st <= ST_DOT_CHUNK;
          end
        end

        ST_NEXT_TILE: begin
          if (tile_base + BK >= S) begin
            recip_req <= 1'b1;
            st <= ST_RECIP;
          end else begin
            tile_base <= tile_base + BK;
            st <= ST_LOAD_KV;
          end
        end

        ST_RECIP:        st <= ST_RECIP_WAIT;

        ST_RECIP_WAIT:   if (recip_valid)
                           st <= ST_QUANT;

        ST_QUANT: begin
          for (int d = 0; d < D; d++) begin
            quant_prod = $signed(sm_acc_flat[d*ACC_W +: ACC_W]) * $signed({1'b0, recip_inv_l});
            o_flat_o[(q_row*D + d)*ELEM_W +: ELEM_W] <= 16'($signed((quant_prod + (96'd1 << 39)) >>> 40));
          end
          st <= ST_NEXT_Q;
        end

        ST_NEXT_Q: begin
          if (q_row == S - 1)
            st <= ST_DONE;
          else begin
            q_row <= q_row + 1'b1;
            st <= ST_LOAD_Q;
          end
        end

        ST_DONE: begin
          busy_o <= 1'b0;
          done_o <= 1'b1;
          st <= ST_IDLE;
        end

        default: st <= ST_IDLE;

      endcase
    end
  end

  assign cycles_o = cycles;
  assign o_data_o = o_flat_o;

endmodule
