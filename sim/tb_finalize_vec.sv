`timescale 1ns/1ps

module tb_finalize_vec;
  localparam int unsigned D = 64;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam int unsigned OUT_W = 16;
  localparam int unsigned FINALIZE_LATENCY = 5;
  localparam int unsigned CASES = 6;

  logic clk;
  logic rst_n;
  logic valid_i;
  logic [L_W-1:0] l_i;
  logic signed [ACC_W-1:0] acc_i [D];
  logic valid_o;
  logic div_zero_o;
  logic signed [OUT_W-1:0] o_q88_o [D];

  logic [L_W-1:0] case_l [CASES];
  logic signed [ACC_W-1:0] case_acc [CASES][D];
  logic signed [OUT_W-1:0] case_out [CASES][D];
  logic case_zero [CASES];

  fa_finalize_vec #(
    .D(D),
    .L_W(L_W),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) dut (
    .clk,
    .rst_n,
    .valid_i,
    .l_i,
    .acc_i,
    .valid_o,
    .div_zero_o,
    .o_q88_o
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic signed [ACC_W-1:0] acc_from_int(
    input integer q88_integer
  );
    begin
      return ACC_W'(q88_integer) <<< 23;
    end
  endfunction

  task automatic init_cases;
    begin
      for (int c = 0; c < CASES; c++) begin
        case_l[c] = '0;
        case_zero[c] = 1'b0;
        for (int lane = 0; lane < D; lane++) begin
          case_acc[c][lane] = '0;
          case_out[c][lane] = '0;
        end
      end

      case_l[0] = 32'h0080_0000;
      case_acc[0][0] = acc_from_int(16'sh0100);
      case_acc[0][1] = acc_from_int(-256);
      case_acc[0][2] = acc_from_int(16'sh0080);
      case_acc[0][63] = acc_from_int(16'sh0040);
      case_out[0][0] = 16'sh0100;
      case_out[0][1] = 16'shff00;
      case_out[0][2] = 16'sh0080;
      case_out[0][63] = 16'sh0040;

      case_l[1] = 32'h0100_0000;
      case_acc[1][0] = acc_from_int(16'sh0180);
      case_acc[1][1] = acc_from_int(16'sh0001);
      case_acc[1][2] = acc_from_int(-1);
      case_acc[1][63] = acc_from_int(16'sh0200);
      case_out[1][0] = 16'sh00c0;
      case_out[1][1] = 16'sh0000;
      case_out[1][2] = 16'sh0000;
      case_out[1][63] = 16'sh0100;

      case_l[2] = 32'h00af_16ac;
      case_acc[2][0] = acc_from_int(16'sh0100);
      case_acc[2][1] = acc_from_int(-256);
      case_acc[2][2] = acc_from_int(16'sh0080);
      case_acc[2][63] = acc_from_int(16'sh0180);
      case_out[2][0] = 16'sh00bb;
      case_out[2][1] = 16'shff45;
      case_out[2][2] = 16'sh005e;
      case_out[2][63] = 16'sh0119;

      case_l[3] = 32'h0000_0000;
      case_acc[3][0] = acc_from_int(16'sh1234);
      case_acc[3][63] = acc_from_int(-4660);
      case_zero[3] = 1'b1;

      case_l[4] = 32'h0080_0000;
      case_acc[4][0] = acc_from_int(32767 + 512);
      case_acc[4][1] = acc_from_int(-32768 - 512);
      case_out[4][0] = 16'sh7fff;
      case_out[4][1] = 16'sh8000;

      case_l[5] = 32'h8000_0000;
      case_acc[5][0] = acc_from_int(16'sh0100);
      case_acc[5][1] = acc_from_int(-256);
      case_acc[5][63] = acc_from_int(16'sh7fff);
      case_out[5][0] = 16'sh0001;
      case_out[5][1] = 16'shffff;
      case_out[5][63] = 16'sh0080;
    end
  endtask

  initial begin
    int cycle;
    int out_case;

    rst_n = 1'b0;
    valid_i = 1'b0;
    l_i = '0;
    for (int lane = 0; lane < D; lane++) begin
      acc_i[lane] = '0;
    end
    init_cases();

    #1;
    if (valid_o !== 1'b0 || div_zero_o !== 1'b0) begin
      $fatal(1, "reset valid/error outputs not clear");
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    for (cycle = 0; cycle < CASES + FINALIZE_LATENCY - 1; cycle++) begin
      @(negedge clk);
      if (cycle < CASES) begin
        valid_i = 1'b1;
        l_i = case_l[cycle];
        for (int lane = 0; lane < D; lane++) begin
          acc_i[lane] = case_acc[cycle][lane];
        end
      end else begin
        valid_i = 1'b0;
        l_i = '0;
        for (int lane = 0; lane < D; lane++) begin
          acc_i[lane] = '0;
        end
      end

      @(posedge clk);
      #1;
      out_case = cycle - (FINALIZE_LATENCY - 1);
      if (out_case >= 0 && out_case < CASES) begin
        if (valid_o !== 1'b1 || div_zero_o !== case_zero[out_case]) begin
          $fatal(1, "case=%0d valid=%0b zero=%0b expected_zero=%0b",
                 out_case, valid_o, div_zero_o, case_zero[out_case]);
        end
        for (int lane = 0; lane < D; lane++) begin
          if (o_q88_o[lane] !== case_out[out_case][lane]) begin
            $fatal(1, "case=%0d lane=%0d output=%04h expected=%04h",
                   out_case, lane, o_q88_o[lane], case_out[out_case][lane]);
          end
        end
      end else if (valid_o !== 1'b0 || div_zero_o !== 1'b0) begin
        $fatal(1, "unexpected output at cycle=%0d", cycle);
      end
    end

    $display("tb_finalize_vec PASS cases=%0d latency=%0d",
             CASES, FINALIZE_LATENCY);
    $finish;
  end
endmodule
