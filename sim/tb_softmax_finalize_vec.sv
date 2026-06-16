`timescale 1ns/1ps

module tb_softmax_finalize_vec;
  localparam int unsigned D = 64;
  localparam int unsigned SCORE_W = 24;
  localparam int unsigned L_W = 32;
  localparam int unsigned ACC_W = 48;
  localparam int unsigned OUT_W = 16;

  localparam logic [L_W-1:0] L_ONE = 32'h0080_0000;
  localparam logic [L_W-1:0] L_TWO = 32'h0100_0000;
  localparam logic [L_W-1:0] L_ONE_PLUS_EXP_NEG_ONE = 32'h00af_16ac;
  localparam logic signed [SCORE_W-1:0] SCORE_ZERO = '0;
  localparam logic signed [SCORE_W-1:0] SCORE_NEG_ONE = -24'sd65536;

  logic clk;
  logic rst_n;

  logic softmax_valid_i;
  logic softmax_row_start_i;
  logic softmax_score_valid_i;
  logic signed [SCORE_W-1:0] softmax_score_i;
  logic signed [15:0] softmax_v_i [D];
  logic softmax_valid_o;
  logic signed [SCORE_W-1:0] softmax_m_o;
  logic [L_W-1:0] softmax_l_o;
  logic signed [ACC_W-1:0] softmax_acc_o [D];

  logic finalize_valid_i;
  logic [L_W-1:0] finalize_l_i;
  logic signed [ACC_W-1:0] finalize_acc_i [D];
  logic finalize_valid_o;
  logic signed [OUT_W-1:0] finalize_o_q88_o [D];

  fa_softmax_online_vec #(
    .D(D),
    .SCORE_W(SCORE_W),
    .L_W(L_W),
    .ACC_W(ACC_W)
  ) u_softmax (
    .clk,
    .rst_n,
    .valid_i(softmax_valid_i),
    .row_start_i(softmax_row_start_i),
    .score_valid_i(softmax_score_valid_i),
    .score_i(softmax_score_i),
    .v_i(softmax_v_i),
    .valid_o(softmax_valid_o),
    .m_o(softmax_m_o),
    .l_o(softmax_l_o),
    .acc_o(softmax_acc_o)
  );

  fa_finalize_vec #(
    .D(D),
    .L_W(L_W),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) u_finalize (
    .clk,
    .rst_n,
    .valid_i(finalize_valid_i),
    .l_i(finalize_l_i),
    .acc_i(finalize_acc_i),
    .valid_o(finalize_valid_o),
    .o_q88_o(finalize_o_q88_o)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  assign finalize_valid_i = softmax_valid_o;
  assign finalize_l_i = softmax_l_o;

  always_comb begin
    for (int lane = 0; lane < D; lane++) begin
      finalize_acc_i[lane] = softmax_acc_o[lane];
    end
  end

  function automatic logic signed [ACC_W-1:0] acc_from_q88(
    input logic signed [15:0] q88
  );
    logic signed [ACC_W-1:0] widened;
    begin
      widened = {{(ACC_W-16){q88[15]}}, q88};
      return widened <<< 23;
    end
  endfunction

  task automatic clear_inputs;
    begin
      softmax_valid_i = 1'b0;
      softmax_row_start_i = 1'b0;
      softmax_score_valid_i = 1'b0;
      softmax_score_i = '0;
      for (int lane = 0; lane < D; lane++) begin
        softmax_v_i[lane] = '0;
      end
    end
  endtask

  task automatic pulse_row_start;
    begin
      @(negedge clk);
      clear_inputs();
      softmax_row_start_i = 1'b1;
      @(negedge clk);
      softmax_row_start_i = 1'b0;
    end
  endtask

  task automatic drive_score_vec(
    input logic signed [SCORE_W-1:0] score,
    input logic signed [15:0] lane00,
    input logic signed [15:0] lane01,
    input logic signed [15:0] lane63
  );
    begin
      @(negedge clk);
      clear_inputs();
      softmax_valid_i = 1'b1;
      softmax_score_valid_i = 1'b1;
      softmax_score_i = score;
      softmax_v_i[0] = lane00;
      softmax_v_i[1] = lane01;
      softmax_v_i[63] = lane63;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic idle_softmax_input;
    begin
      @(negedge clk);
      clear_inputs();
    end
  endtask

  task automatic check_softmax_meta(
    input string tag,
    input logic signed [SCORE_W-1:0] expected_m,
    input logic [L_W-1:0] expected_l
  );
    begin
      if (softmax_valid_o !== 1'b1) begin
        $fatal(1, "%s softmax valid_o=%0b expected=1", tag, softmax_valid_o);
      end

      if (softmax_m_o !== expected_m || softmax_l_o !== expected_l) begin
        $fatal(1, "%s softmax m=%0d l=0x%08h expected m=%0d l=0x%08h",
               tag, softmax_m_o, softmax_l_o, expected_m, expected_l);
      end
    end
  endtask

  task automatic check_softmax_lane(
    input string tag,
    input int unsigned lane,
    input logic signed [ACC_W-1:0] expected
  );
    begin
      if (softmax_acc_o[lane] !== expected) begin
        $fatal(1, "%s softmax lane%0d acc=0x%012h expected=0x%012h",
               tag, lane, softmax_acc_o[lane], expected);
      end
    end
  endtask

  task automatic wait_finalize_valid(input string tag);
    begin
      for (int guard = 0; guard < 16; guard++) begin
        @(posedge clk);
        #1;
        if (finalize_valid_o === 1'b1) begin
          return;
        end
      end

      $fatal(1, "%s finalize valid_o timeout", tag);
    end
  endtask

  task automatic check_finalize_lane(
    input string tag,
    input int unsigned lane,
    input logic signed [OUT_W-1:0] expected
  );
    begin
      if (finalize_o_q88_o[lane] !== expected) begin
        $fatal(1, "%s finalize lane%0d o_q88=0x%04h expected=0x%04h",
               tag, lane, finalize_o_q88_o[lane], expected);
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    clear_inputs();

    #1;
    if (softmax_valid_o !== 1'b0 || finalize_valid_o !== 1'b0) begin
      $fatal(1, "reset valid outputs not clear");
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    pulse_row_start();

    drive_score_vec(SCORE_ZERO, 16'sh0100, 16'shff00, 16'sh0200);
    check_softmax_meta("equal_first", SCORE_ZERO, L_ONE);
    check_softmax_lane("equal_first", 0, acc_from_q88(16'sh0100));
    check_softmax_lane("equal_first", 1, acc_from_q88(16'shff00));
    check_softmax_lane("equal_first", 63, acc_from_q88(16'sh0200));

    drive_score_vec(SCORE_ZERO, 16'sh0080, 16'sh0100, 16'shff00);
    check_softmax_meta("equal_final", SCORE_ZERO, L_TWO);
    check_softmax_lane("equal_final", 0, 48'sh0000_c000_0000);
    check_softmax_lane("equal_final", 1, 48'sh0000_0000_0000);
    check_softmax_lane("equal_final", 63, 48'sh0000_8000_0000);
    idle_softmax_input();

    wait_finalize_valid("equal_first");
    check_finalize_lane("equal_first", 0, 16'sh0100);
    check_finalize_lane("equal_first", 1, 16'shff00);
    check_finalize_lane("equal_first", 63, 16'sh0200);

    wait_finalize_valid("equal_final");
    check_finalize_lane("equal_final", 0, 16'sh00c0);
    check_finalize_lane("equal_final", 1, 16'sh0000);
    check_finalize_lane("equal_final", 63, 16'sh0080);

    pulse_row_start();

    drive_score_vec(SCORE_ZERO, 16'sh0100, 16'sh0000, 16'sh0000);
    check_softmax_meta("lower_first", SCORE_ZERO, L_ONE);
    check_softmax_lane("lower_first", 0, acc_from_q88(16'sh0100));

    drive_score_vec(SCORE_NEG_ONE, 16'sh0200, 16'sh0000, 16'sh0000);
    check_softmax_meta("lower_final", SCORE_ZERO, L_ONE_PLUS_EXP_NEG_ONE);
    check_softmax_lane("lower_final", 0, 48'sh0000_de2d_5800);
    idle_softmax_input();

    wait_finalize_valid("lower_first");
    check_finalize_lane("lower_first", 0, 16'sh0100);

    wait_finalize_valid("lower_final");
    check_finalize_lane("lower_final", 0, 16'sh0145);

    $display("tb_softmax_finalize_vec PASS equal_l=0x%08h equal_o00=0x%04h equal_o01=0x%04h equal_o63=0x%04h lower_l=0x%08h lower_o00=0x%04h",
             L_TWO, 16'h00c0, 16'h0000, 16'h0080, L_ONE_PLUS_EXP_NEG_ONE,
             16'h0145);
    $finish;
  end
endmodule
