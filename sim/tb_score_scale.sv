`timescale 1ns/1ps

module tb_score_scale;
  localparam int unsigned SCORE_W = 48;

  logic signed [SCORE_W-1:0] raw_dot_i;
  logic signed [SCORE_W-1:0] scaled_score_o;

  fa_score_scale #(
    .SCORE_W(SCORE_W)
  ) dut (
    .raw_dot_i,
    .scaled_score_o
  );

  task automatic check_case(
    input string name,
    input logic signed [SCORE_W-1:0] raw_dot,
    input logic signed [SCORE_W-1:0] expected
  );
    begin
      raw_dot_i = raw_dot;
      #1;
      if (scaled_score_o !== expected) begin
        $fatal(1, "%s: scaled_score_o=%0d expected=%0d raw_dot=%0d",
               name, scaled_score_o, expected, raw_dot);
      end
    end
  endtask

  initial begin
    raw_dot_i = '0;

    check_case("zero", 48'sd0, 48'sd0);
    check_case("positive_exact", 48'sd64, 48'sd8);
    check_case("negative_exact", -48'sd64, -48'sd8);
    check_case("positive_nondivisible_below_half", 48'sd3, 48'sd0);
    check_case("positive_nondivisible_at_half", 48'sd4, 48'sd0);
    check_case("positive_nondivisible_above_half", 48'sd7, 48'sd0);
    check_case("negative_nondivisible_below_half", -48'sd3, -48'sd1);
    check_case("negative_nondivisible_at_half", -48'sd4, -48'sd1);
    check_case("negative_nondivisible_above_half", -48'sd7, -48'sd1);
    check_case("positive_mixed_fraction", 48'sd12, 48'sd1);
    check_case("negative_mixed_fraction", -48'sd12, -48'sd2);

    $display("tb_score_scale PASS");
    $finish;
  end
endmodule
