`timescale 1ns/1ps

module fa_softmax_online #(
  parameter SCORE_W      = 24,
  parameter EXP_W        = 16,
  parameter L_W          = 32,
  parameter ACC_W        = 48,
  parameter V_ACC_LANES  = 16,
  parameter D            = 64
) (
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         row_start_i,
  input  logic                         score_valid_i,
  input  logic signed [SCORE_W-1:0]    score_i,
  input   logic signed [15:0]     v_i   [V_ACC_LANES],
  input  logic                         v_valid_i,
  input  logic                         last_tile_i,

  output logic                         ready_o,
  output logic signed [SCORE_W-1:0]    m_o,
  output logic        [L_W-1:0]        l_o,
  output logic signed [ACC_W-1:0]      acc_o [D],
  output logic                         done_o,
  output logic signed [15:0]           o_elem_o [D],
  output logic signed [D*ACC_W-1:0]    acc_o_flat
);

  localparam V_CYCLES = D / V_ACC_LANES;
  localparam signed NEG_LARGE = -24'sh800000;  // most negative Q8.16 (~ -128.0)

  logic signed [SCORE_W-1:0] m_q;
  logic [L_W-1:0]            l_q;
  logic signed [ACC_W-1:0]   acc_q [D];

  // P path: exp(score - m_new)
  logic signed [15:0] p_diff_q88;
  logic               p_exp_req;
  logic [EXP_W-1:0]   P_val;
  logic               P_valid;

  // Alpha path: exp(m - m_new), only when new max is found
  logic signed [15:0] alpha_diff_q88;
  logic               alpha_exp_req;
  logic [EXP_W-1:0]   alpha_exp_val;
  logic               alpha_exp_valid;
  logic               alpha_override;    // force alpha=1.0 when no new max
  logic [EXP_W-1:0]   alpha_val;
  logic               alpha_valid;

  logic signed [SCORE_W-1:0] m_prev;
  logic signed [SCORE_W-1:0] m_new;

  // ST_ACCUM temporary variables (module-level for iverilog compat)
  logic signed [32:0] P_s;
  logic signed [31:0] V_s;
  logic signed [63:0] vacc_prod;
  logic                     new_max;

  logic [47:0] l_scaled;
  logic signed [ACC_W-1:0] acc_scaled_q [D];

  logic [2:0]  v_cnt;
  logic        alpha_needed;

  // Mux: when override set, alpha = 1.0 (0xFFFF) immediately
  assign alpha_val   = alpha_override ? 16'hFFFF : alpha_exp_val;
  assign alpha_valid = alpha_override ? 1'b1      : alpha_exp_valid;

  typedef enum logic [2:0] {ST_IDLE, ST_EXP, ST_ALPHA, ST_ACCUM, ST_DONE} st_e;
  st_e st;

  // Dual exp modules — P and alpha can be computed in parallel
  fa_exp_approx #(.IN_W(16), .OUT_W(EXP_W)) u_exp_P (
    .clk    (clk),
    .rst_n  (rst_n),
    .valid_i(p_exp_req),
    .x_i    (p_diff_q88),
    .valid_o(P_valid),
    .y_o    (P_val)
  );

  fa_exp_approx #(.IN_W(16), .OUT_W(EXP_W)) u_exp_alpha (
    .clk    (clk),
    .rst_n  (rst_n),
    .valid_i(alpha_exp_req),
    .x_i    (alpha_diff_q88),
    .valid_o(alpha_exp_valid),
    .y_o    (alpha_exp_val)
  );

  assign m_o = m_q;
  assign l_o = l_q;

  // Combinational l and acc rescaling
  always_comb begin
    // Use 64-bit to prevent overflow: l_q*alpha can exceed 32-bit
    l_scaled = (64'(l_q) * 64'(alpha_val)) >>> 16;
  end

  integer acc_i;
  always_comb begin
    for (acc_i = 0; acc_i < D; acc_i = acc_i + 1) begin
      // Use 64-bit operands to prevent product overflow in 48-bit context
      acc_scaled_q[acc_i] = alpha_needed
        ? 48'((64'(acc_q[acc_i]) * 64'($signed({1'b0, alpha_val}))) >>> 16)
        : acc_q[acc_i];
    end
  end

  // Packed output for iverilog compatibility (unpacked array ports broken)
  integer pi;
  always_comb begin
    for (pi = 0; pi < D; pi = pi + 1)
      acc_o_flat[pi*ACC_W +: ACC_W] = acc_q[pi];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st            <= ST_IDLE;
      m_q           <= NEG_LARGE;
      l_q           <= '0;
      p_exp_req     <= 1'b0;
      alpha_exp_req <= 1'b0;
      alpha_override <= 1'b1;
      v_cnt         <= '0;
      done_o        <= 1'b0;
      ready_o       <= 1'b1;

      for (int i = 0; i < D; i++) begin
        acc_q[i]    <= '0;
        acc_o[i]    <= '0;
        o_elem_o[i] <= '0;
      end
    end else begin
      // Defaults
      done_o  <= 1'b0;
      p_exp_req <= 1'b0;
      alpha_exp_req <= 1'b0;

      if (row_start_i) begin
        m_q   <= NEG_LARGE;
        l_q   <= '0;
        for (int i = 0; i < D; i++) begin
          acc_q[i] <= '0;
          acc_o[i] <= '0;
        end
        // SM_INIT: row reset complete
      end

      unique case (st)
        ST_IDLE: begin
          ready_o <= 1'b1;
          if (score_valid_i) begin
            ready_o <= 1'b0;

            m_prev <= m_q;
            m_new  <= (score_i > m_q) ? score_i : m_q;
            new_max <= (score_i > m_q);
            alpha_needed <= (m_q != NEG_LARGE) && (score_i > m_q);

            // P = exp(score - m_new) — always needed
            p_diff_q88 <= (score_i > m_q)
              ? 16'sd0
              : (score_i - m_q) >>> 8;
            p_exp_req <= 1'b1;

            // Alpha = exp(m - m_new) — only when new max found
            if ((m_q != NEG_LARGE) && (score_i > m_q)) begin
              alpha_diff_q88 <= (m_q - score_i) >>> 8;
              alpha_exp_req  <= 1'b1;
              alpha_override <= 1'b0;
            end else begin
              alpha_override <= 1'b1;  // alpha = 1.0 when no new max
            end

            st <= ST_EXP;
          end
        end

        ST_EXP: begin
          // Wait for P exp (always 1 cycle)
          // Alpha exp is either already valid (alpha=1.0) or comes 1 cycle after request
          if (P_valid) begin
            if (!alpha_needed || (alpha_needed && alpha_valid)) begin
              // Apply l update
              l_q <= l_scaled + {{(L_W-EXP_W){1'b0}}, P_val};

              // Apply acc rescaling
              for (int i = 0; i < D; i++) begin
                acc_q[i] <= acc_scaled_q[i];
                acc_o[i] <= acc_scaled_q[i];
              end
              // L and acc rescaling applied

              m_q     <= m_new;
              v_cnt   <= '0;
              st      <= ST_ACCUM;
            end else begin
              // Wait one more cycle for alpha exp
              st <= ST_ALPHA;
            end
          end
        end

        ST_ALPHA: begin
          if (alpha_valid) begin
            alpha_exp_req <= 1'b0;
            l_q <= l_scaled + {{(L_W-EXP_W){1'b0}}, P_val};

            for (int i = 0; i < D; i++) begin
              acc_q[i] <= acc_scaled_q[i];
              acc_o[i] <= acc_scaled_q[i];
            end

            m_q   <= m_new;
            v_cnt <= '0;
            st    <= ST_ACCUM;
          end
        end

        ST_ACCUM: begin
          if (v_valid_i) begin
            for (int i = 0; i < V_ACC_LANES; i++) begin
              P_s = $signed({1'b0, P_val});
              V_s = v_i[i];
              vacc_prod = P_s * V_s;
              acc_q[v_cnt * V_ACC_LANES + i]
                <= acc_q[v_cnt * V_ACC_LANES + i] + (ACC_W'(vacc_prod) <<< 8);
              acc_o[v_cnt * V_ACC_LANES + i]
                <= acc_q[v_cnt * V_ACC_LANES + i] + (ACC_W'(vacc_prod) <<< 8);
            end

            if (v_cnt == V_CYCLES - 1) begin
              v_cnt   <= '0;
              ready_o <= 1'b1;
              if (last_tile_i)
                st <= ST_DONE;
              else
                st <= ST_IDLE;
            end else begin
              v_cnt <= v_cnt + 1'b1;
            end
          end
        end

        ST_DONE: begin
          done_o  <= 1'b1;
          ready_o <= 1'b1;
          st      <= ST_IDLE;
        end

        default: begin
          st      <= ST_IDLE;
          ready_o <= 1'b1;
        end
      endcase
    end
  end

endmodule
