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
  output logic [OUT_W-1:0]     y_o,
  output logic                 div_zero_o
);
  logic                 valid_s1_q;
  logic                 zero_s1_q;
  logic [31:0]          mantissa_s1_q;
  logic signed [5:0]    exponent_s1_q;
  logic [4:0]           seed_index_s1_q;
  logic [31:0]          seed_s1_q;

  logic                 valid_s2_q;
  logic                 zero_s2_q;
  logic signed [5:0]    exponent_s2_q;
  logic [31:0]          seed_s2_q;
  logic [32:0]          my_s2_q;

  logic                 valid_s3_q;
  logic                 zero_s3_q;
  logic signed [5:0]    exponent_s3_q;
  logic [31:0]          nr_iter_s3_q;

  logic                 zero_s1_next;
  logic [31:0]          mantissa_s1_next;
  logic signed [5:0]    exponent_s1_next;
  logic [4:0]           seed_index_s1_next;
  logic [31:0]          seed_s1_next;
  logic [5:0]           msb_index;

  logic [63:0]          my_product_s2;
  logic [32:0]          correction_s3;
  logic [64:0]          nr_product_s3;
  logic [33:0]          nr_shifted_s3;
  logic [31:0]          nr_iter_s3_next;
  logic [63:0]          denorm_shifted_s4;
  logic [31:0]          y_s4_next;

  function automatic logic [31:0] seed_lut(input logic [4:0] index);
    begin
      case (index)
         0: seed_lut = 32'h7e07e07e;
         1: seed_lut = 32'h7a44c6b0;
         2: seed_lut = 32'h76b981db;
         3: seed_lut = 32'h73615a24;
         4: seed_lut = 32'h70381c0e;
         5: seed_lut = 32'h6d3a06d4;
         6: seed_lut = 32'h6a63bd82;
         7: seed_lut = 32'h67b23a54;
         8: seed_lut = 32'h6522c3f3;
         9: seed_lut = 32'h62b2e43e;
        10: seed_lut = 32'h60606060;
        11: seed_lut = 32'h5e293206;
        12: seed_lut = 32'h5c0b8170;
        13: seed_lut = 32'h5a05a05a;
        14: seed_lut = 32'h58160581;
        15: seed_lut = 32'h563b48c2;
        16: seed_lut = 32'h54741fac;
        17: seed_lut = 32'h52bf5a81;
        18: seed_lut = 32'h511be196;
        19: seed_lut = 32'h4f88b2f4;
        20: seed_lut = 32'h4e04e04e;
        21: seed_lut = 32'h4c8f8d29;
        22: seed_lut = 32'h4b27ed36;
        23: seed_lut = 32'h49cd42e2;
        24: seed_lut = 32'h487ede05;
        25: seed_lut = 32'h473c1ab7;
        26: seed_lut = 32'h46046046;
        27: seed_lut = 32'h44d72045;
        28: seed_lut = 32'h43b3d5b0;
        29: seed_lut = 32'h429a042a;
        30: seed_lut = 32'h4189374c;
        default: seed_lut = 32'h40810204;
      endcase
    end
  endfunction

  always_comb begin
    zero_s1_next = (x_i == '0);
    msb_index = '0;
    for (int bit_index = 0; bit_index < 32; bit_index++) begin
      if (x_i[bit_index]) begin
        msb_index = 6'(bit_index);
      end
    end

    if (zero_s1_next) begin
      mantissa_s1_next = '0;
      exponent_s1_next = '0;
      seed_index_s1_next = '0;
      seed_s1_next = '0;
    end else begin
      mantissa_s1_next = x_i << (31 - msb_index);
      exponent_s1_next = $signed({1'b0, msb_index}) - 6'sd23;
      seed_index_s1_next = mantissa_s1_next[30:26];
      seed_s1_next = seed_lut(seed_index_s1_next);
    end
  end

  assign my_product_s2 = mantissa_s1_q * seed_s1_q;
  assign correction_s3 = 33'h1_0000_0000 - my_s2_q;
  assign nr_product_s3 = seed_s2_q * correction_s3;
  assign nr_shifted_s3 = nr_product_s3 >> 31;
  assign nr_iter_s3_next =
      (|nr_shifted_s3[33:32]) ? 32'hffff_ffff : nr_shifted_s3[31:0];

  always_comb begin
    denorm_shifted_s4 = '0;
    if (zero_s3_q) begin
      y_s4_next = '0;
    end else if (exponent_s3_q >= 0) begin
      y_s4_next = nr_iter_s3_q >> exponent_s3_q;
    end else begin
      denorm_shifted_s4 =
          {32'b0, nr_iter_s3_q} << (-exponent_s3_q);
      y_s4_next =
          (|denorm_shifted_s4[63:32]) ?
          32'hffff_ffff : denorm_shifted_s4[31:0];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s1_q <= 1'b0;
      zero_s1_q <= 1'b0;
      mantissa_s1_q <= '0;
      exponent_s1_q <= '0;
      seed_index_s1_q <= '0;
      seed_s1_q <= '0;

      valid_s2_q <= 1'b0;
      zero_s2_q <= 1'b0;
      exponent_s2_q <= '0;
      seed_s2_q <= '0;
      my_s2_q <= '0;

      valid_s3_q <= 1'b0;
      zero_s3_q <= 1'b0;
      exponent_s3_q <= '0;
      nr_iter_s3_q <= '0;

      valid_o <= 1'b0;
      y_o <= '0;
      div_zero_o <= 1'b0;
    end else begin
      valid_s1_q <= valid_i;
      zero_s1_q <= valid_i && zero_s1_next;
      mantissa_s1_q <= valid_i ? mantissa_s1_next : '0;
      exponent_s1_q <= valid_i ? exponent_s1_next : '0;
      seed_index_s1_q <= valid_i ? seed_index_s1_next : '0;
      seed_s1_q <= valid_i ? seed_s1_next : '0;

      valid_s2_q <= valid_s1_q;
      zero_s2_q <= valid_s1_q && zero_s1_q;
      exponent_s2_q <= valid_s1_q ? exponent_s1_q : '0;
      seed_s2_q <= valid_s1_q ? seed_s1_q : '0;
      my_s2_q <= valid_s1_q ? (my_product_s2 >> 31) : '0;

      valid_s3_q <= valid_s2_q;
      zero_s3_q <= valid_s2_q && zero_s2_q;
      exponent_s3_q <= valid_s2_q ? exponent_s2_q : '0;
      nr_iter_s3_q <= valid_s2_q ? nr_iter_s3_next : '0;

      valid_o <= valid_s3_q;
      y_o <= valid_s3_q ? OUT_W'(y_s4_next) : '0;
      div_zero_o <= valid_s3_q && zero_s3_q;
    end
  end
endmodule
