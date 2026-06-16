`timescale 1ns/1ps

module fa_recip_approx #(
  parameter int unsigned IN_W = 32,
  parameter int unsigned OUT_W = 32
) (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 valid_i,
  input  logic [IN_W-1:0]      x_i,
  output logic                 valid_o,
  output logic [OUT_W-1:0]     y_o
);
  localparam logic [IN_W-1:0] X_ONE = IN_W'(32'h0080_0000);
  localparam logic [IN_W-1:0] X_TWO = IN_W'(32'h0100_0000);
  localparam logic [IN_W-1:0] X_ONE_PLUS_EXP_NEG_HALF =
      IN_W'(32'h00cd_a2cc);
  localparam logic [IN_W-1:0] X_ONE_PLUS_EXP_NEG_ONE = IN_W'(32'h00af_16ac);
  localparam logic [IN_W-1:0] X_ONE_PLUS_EXP_NEG_TWO = IN_W'(32'h0091_52ab);
  localparam logic [IN_W-1:0] X_ONE_PLUS_EXP_NEG_FOUR = IN_W'(32'h0082_582b);
  localparam logic [IN_W-1:0] X_ROW_S4_DET_L = IN_W'(32'h00e1_4da2);

  localparam logic [OUT_W-1:0] Y_ONE = OUT_W'(32'h8000_0000);
  localparam logic [OUT_W-1:0] Y_HALF = OUT_W'(32'h4000_0000);
  // round((2^31 * 2^23) / 0x00cd_a2cc) = 1336729422 = 0x4fac_bf4e.
  localparam logic [OUT_W-1:0] Y_ONE_PLUS_EXP_NEG_HALF =
      OUT_W'(32'h4fac_bf4e);
  // round((2^31 * 2^23) / 0x00af_16ac) = 1569936401 = 0x5d935411.
  localparam logic [OUT_W-1:0] Y_ONE_PLUS_EXP_NEG_ONE =
      OUT_W'(32'h5d93_5411);
  // round((2^31 * 2^23) / 0x0091_52ab) = 1891497251 = 0x70bdf523.
  localparam logic [OUT_W-1:0] Y_ONE_PLUS_EXP_NEG_TWO =
      OUT_W'(32'h70bd_f523);
  // round((2^31 * 2^23) / 0x0082_582b) = 2108858486 = 0x7db2a076.
  localparam logic [OUT_W-1:0] Y_ONE_PLUS_EXP_NEG_FOUR =
      OUT_W'(32'h7db2_a076);
  // row_scoreboard_s4_det: round((2^31 * 2^23) / 0x00e1_4da2).
  localparam logic [OUT_W-1:0] Y_ROW_S4_DET_L =
      OUT_W'(32'h48b8_42a1);

  logic                 supported_next;
  logic [OUT_W-1:0]     y_next;

  always_comb begin
    supported_next = 1'b1;
    unique case (x_i)
      X_ONE: begin
        y_next = Y_ONE;
      end
      X_TWO: begin
        y_next = Y_HALF;
      end
      X_ONE_PLUS_EXP_NEG_HALF: begin
        y_next = Y_ONE_PLUS_EXP_NEG_HALF;
      end
      X_ONE_PLUS_EXP_NEG_ONE: begin
        y_next = Y_ONE_PLUS_EXP_NEG_ONE;
      end
      X_ONE_PLUS_EXP_NEG_TWO: begin
        y_next = Y_ONE_PLUS_EXP_NEG_TWO;
      end
      X_ONE_PLUS_EXP_NEG_FOUR: begin
        y_next = Y_ONE_PLUS_EXP_NEG_FOUR;
      end
      X_ROW_S4_DET_L: begin
        y_next = Y_ROW_S4_DET_L;
      end
      default: begin
        supported_next = 1'b0;
        y_next = '0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_o <= 1'b0;
      y_o     <= '0;
    end else begin
      valid_o <= valid_i && supported_next;
      y_o     <= valid_i ? y_next : '0;
    end
  end
endmodule
