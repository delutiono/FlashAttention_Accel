`timescale 1ns/1ps

module tb_recip_approx;
  localparam int unsigned IN_W = 32;
  localparam int unsigned OUT_W = 32;
  localparam int unsigned LATENCY = 4;
  localparam int unsigned MAX_CASES = 80;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic [IN_W-1:0] x_i;
  logic valid_o;
  logic [OUT_W-1:0] y_o;
  logic div_zero_o;

  logic [31:0] case_x [MAX_CASES];
  logic [31:0] exp_m [MAX_CASES];
  logic signed [5:0] exp_e [MAX_CASES];
  logic [4:0] exp_idx [MAX_CASES];
  logic [31:0] exp_seed [MAX_CASES];
  logic [32:0] exp_my [MAX_CASES];
  logic [31:0] exp_nr [MAX_CASES];
  logic [31:0] exp_y [MAX_CASES];
  logic exp_zero [MAX_CASES];
  int case_count;

  fa_recip_approx #(
    .IN_W(IN_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .x_i,
    .valid_o,
    .y_o,
    .div_zero_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

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

  task automatic add_case(input logic [31:0] value);
    int msb;
    logic [31:0] mantissa;
    logic signed [5:0] exponent;
    logic [4:0] index;
    logic [31:0] seed;
    logic [63:0] product;
    logic [32:0] my;
    logic [32:0] correction;
    logic [64:0] refined_product;
    logic [32:0] refined_wide;
    logic [31:0] refined;
    logic [63:0] shifted;
    begin
      case_x[case_count] = value;
      if (value == 0) begin
        exp_m[case_count] = '0;
        exp_e[case_count] = '0;
        exp_idx[case_count] = '0;
        exp_seed[case_count] = '0;
        exp_my[case_count] = '0;
        exp_nr[case_count] = '0;
        exp_y[case_count] = '0;
        exp_zero[case_count] = 1'b1;
      end else begin
        msb = 31;
        while (!value[msb]) begin
          msb--;
        end
        mantissa = value << (31 - msb);
        exponent = msb - 23;
        index = mantissa[30:26];
        seed = seed_lut(index);
        product = mantissa * seed;
        my = product >> 31;
        correction = 33'h1_0000_0000 - my;
        refined_product = seed * correction;
        refined_wide = refined_product >> 31;
        refined = refined_wide[32] ? 32'hffff_ffff : refined_wide[31:0];

        exp_m[case_count] = mantissa;
        exp_e[case_count] = exponent;
        exp_idx[case_count] = index;
        exp_seed[case_count] = seed;
        exp_my[case_count] = my;
        exp_nr[case_count] = refined;
        if (exponent >= 0) begin
          exp_y[case_count] = refined >> exponent;
        end else begin
          shifted = {32'b0, refined} << (-exponent);
          exp_y[case_count] =
              (|shifted[63:32]) ? 32'hffff_ffff : shifted[31:0];
        end
        exp_zero[case_count] = 1'b0;
      end
      case_count++;
    end
  endtask

  task automatic check_trace(input int issued, input int cycle);
    int s1;
    int s2;
    int s3;
    int out_idx;
    begin
      s1 = cycle;
      s2 = cycle - 1;
      s3 = cycle - 2;
      out_idx = cycle - (LATENCY - 1);

      if (s1 >= 0 && s1 < issued) begin
        if (dut.mantissa_s1_q !== exp_m[s1] ||
            dut.exponent_s1_q !== exp_e[s1] ||
            dut.seed_index_s1_q !== exp_idx[s1] ||
            dut.seed_s1_q !== exp_seed[s1]) begin
          $fatal(1, "s1 trace case=%0d x=%08h m=%08h/%08h e=%0d/%0d idx=%0d/%0d seed=%08h/%08h",
                 s1, case_x[s1], dut.mantissa_s1_q, exp_m[s1],
                 dut.exponent_s1_q, exp_e[s1], dut.seed_index_s1_q,
                 exp_idx[s1], dut.seed_s1_q, exp_seed[s1]);
        end
      end
      if (s2 >= 0 && s2 < issued && dut.valid_s2_q) begin
        if (dut.my_s2_q !== exp_my[s2]) begin
          $fatal(1, "s2 trace case=%0d x=%08h my=%09h expected=%09h",
                 s2, case_x[s2], dut.my_s2_q, exp_my[s2]);
        end
      end
      if (s3 >= 0 && s3 < issued && dut.valid_s3_q) begin
        if (dut.nr_iter_s3_q !== exp_nr[s3]) begin
          $fatal(1, "s3 trace case=%0d x=%08h nr=%08h expected=%08h",
                 s3, case_x[s3], dut.nr_iter_s3_q, exp_nr[s3]);
        end
      end

      if (out_idx >= 0 && out_idx < issued) begin
        if (valid_o !== 1'b1 || y_o !== exp_y[out_idx] ||
            div_zero_o !== exp_zero[out_idx]) begin
          $fatal(1, "output case=%0d x=%08h valid=%0b y=%08h/%08h zero=%0b/%0b",
                 out_idx, case_x[out_idx], valid_o, y_o, exp_y[out_idx],
                 div_zero_o, exp_zero[out_idx]);
        end
      end else if (valid_o !== 1'b0) begin
        $fatal(1, "unexpected valid_o at cycle=%0d", cycle);
      end
    end
  endtask

  initial begin
    int boundary;
    int cycle;

    rst_n = 1'b0;
    valid_i = 1'b0;
    x_i = '0;
    case_count = 0;

    add_case(32'h0000_0000);
    add_case(32'h0000_0001);
    add_case(32'h0000_0002);
    add_case(32'h007f_ffff);
    add_case(32'h0080_0000);
    add_case(32'h0100_0000);
    add_case(32'h8000_0000);
    add_case(32'h00af_16ac);
    add_case(32'hffff_ffff);

    if (exp_y[0] !== 32'h0000_0000 || !exp_zero[0] ||
        exp_y[4] !== 32'h7ff8_3e87 ||
        exp_y[5] !== 32'h3ffc_1f43 ||
        exp_y[6] !== 32'h007f_f83e ||
        exp_m[7] !== 32'haf16_ac00 ||
        exp_e[7] !== 6'sd0 ||
        exp_idx[7] !== 5'd11 ||
        exp_seed[7] !== 32'h5e29_3206 ||
        exp_my[7] !== 33'h0_80cd_0000 ||
        exp_nr[7] !== 32'h5d92_640b ||
        exp_y[7] !== 32'h5d92_640b) begin
      $fatal(1, "frozen reciprocal checkpoints do not match model/recip_nr.py");
    end

    for (boundary = 1; boundary < 32; boundary++) begin
      add_case(32'h0080_0000 + (boundary << 18) - 1);
      add_case(32'h0080_0000 + (boundary << 18));
    end

    #1;
    if (valid_o !== 1'b0 || y_o !== '0 || div_zero_o !== 1'b0) begin
      $fatal(1, "reset outputs not clear");
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    for (cycle = 0; cycle < case_count + LATENCY - 1; cycle++) begin
      @(negedge clk);
      if (cycle < case_count) begin
        valid_i = 1'b1;
        x_i = case_x[cycle];
      end else begin
        valid_i = 1'b0;
        x_i = '0;
      end
      @(posedge clk);
      #1;
      check_trace(case_count, cycle);
    end

    @(negedge clk);
    valid_i = 1'b0;
    @(posedge clk);
    #1;
    if (valid_o !== 1'b0 || div_zero_o !== 1'b0) begin
      $fatal(1, "pipeline did not return idle");
    end

    $display("tb_recip_approx PASS cases=%0d latency=%0d", case_count, LATENCY);
    $finish;
  end
endmodule
