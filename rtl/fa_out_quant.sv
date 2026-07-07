`timescale 1ns/1ps

module fa_out_quant #(
  parameter ACC_W  = 48,
  parameter INV_W  = 32,
  parameter OUT_W  = 16,
  parameter LANES  = 16,
  parameter D      = 64
) (
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         valid_i,
  input  logic signed [ACC_W-1:0]      acc_i [LANES],
  input  logic        [INV_W-1:0]      inv_l_i,
  input  logic                         last_i,

  output logic                         ready_o,
  output logic                         valid_o,
  output logic signed [OUT_W-1:0]      o_o [LANES]
);

  localparam STAGES = D / LANES;
  localparam signed Q88_MIN = -32768;
  localparam signed Q88_MAX =  32767;

  logic [6:0] cnt;
  logic       active;

  logic signed [ACC_W-1:0]     acc_r [LANES];
  logic        [INV_W-1:0]     inv_l_r;

  // Pipeline stage 1: register inputs, start multiply
  logic               st1_valid;
  logic signed [ACC_W-1:0] acc_s1 [LANES];
  logic signed [95:0] mul_s1 [LANES];  // ACC_W + INV_W bits

  logic               st2_valid;
  logic signed [95:0] mul_s2 [LANES];

  assign ready_o = !active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active   <= 1'b0;
      cnt      <= '0;
      st1_valid <= 1'b0;
      st2_valid <= 1'b0;
      valid_o  <= 1'b0;
      for (int i = 0; i < LANES; i++)
        o_o[i] <= '0;
    end else begin
      valid_o <= 1'b0;

      if (valid_i && ready_o) begin
        active <= 1'b1;
        cnt    <= '0;
        for (int i = 0; i < LANES; i++) begin
          acc_r[i]  <= acc_i[i];
        end
        inv_l_r <= inv_l_i;
      end

      if (active) begin
        // Stage 1: multiply acc * inv_l for LANES elements
        for (int i = 0; i < LANES; i++) begin
          logic signed [ACC_W:0] a;
          logic signed [INV_W:0] b;
          a = $signed({acc_r[i][ACC_W-1], acc_r[i]});
          b = $signed({1'b0, inv_l_r});
          mul_s1[i] <= a * b;
        end
        st1_valid <= 1'b1;
        cnt <= cnt + 7'd1;

        // Stage 2: shift and round
        if (st1_valid) begin
          for (int i = 0; i < LANES; i++)
            mul_s2[i] <= mul_s1[i];
          st2_valid <= 1'b1;

          if (st2_valid) begin
            for (int i = 0; i < LANES; i++) begin
              logic signed [95:0] rounded;
              rounded = mul_s2[i] + (96'd1 << 39);
              o_o[i] <= ($signed(rounded >>> 40) > Q88_MAX) ? Q88_MAX :
                        ($signed(rounded >>> 40) < Q88_MIN) ? Q88_MIN :
                        OUT_W'($signed(rounded >>> 40));
            end
            valid_o <= 1'b1;

            if (cnt == STAGES && last_i) begin
              active  <= 1'b0;
              st1_valid <= 1'b0;
              st2_valid <= 1'b0;
            end
          end
        end
      end
    end
  end

endmodule
