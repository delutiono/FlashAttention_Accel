`timescale 1ns/1ps

module tb_group_engine_tile;
  import fa_pkg::*;

  localparam int unsigned D = FA_D;
  localparam int unsigned ELEM_W = FA_ELEM_W;
  localparam int unsigned GROUP_ROWS = FA_Q_GROUP_ROWS;

  logic clk;
  logic rst_n;

  logic init_valid;
  logic init_ready;
  logic [2:0] init_context;

  logic score_valid;
  logic score_ready;
  logic [2:0] score_context;
  logic [7:0] q_index;
  logic [7:0] k_index;
  logic score_last;
  logic signed [ELEM_W-1:0] q_row [D];
  logic signed [ELEM_W-1:0] k_row [D];
  logic signed [ELEM_W-1:0] v_row [D];

  logic context_done_valid;
  logic [2:0] context_done;
  logic final_valid;
  logic [2:0] final_context;
  logic div_zero;
  logic signed [ELEM_W-1:0] final_row [D];

  int unsigned final_count;

  fa_group_engine #(
    .D(D),
    .GROUP_ROWS(GROUP_ROWS),
    .ELEM_W(ELEM_W)
  ) dut (
    .clk,
    .rst_n,
    .init_valid_i(init_valid),
    .init_ready_o(init_ready),
    .init_context_i(init_context),
    .score_valid_i(score_valid),
    .score_ready_o(score_ready),
    .score_context_i(score_context),
    .q_index_i(q_index),
    .k_index_i(k_index),
    .score_last_i(score_last),
    .q_i(q_row),
    .k_i(k_row),
    .v_i(v_row),
    .context_done_valid_o(context_done_valid),
    .context_done_o(context_done),
    .final_valid_o(final_valid),
    .final_context_o(final_context),
    .div_zero_o(div_zero),
    .final_o(final_row)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic fail(input string message);
    begin
      $error("%s", message);
      $fatal(1);
    end
  endtask

  task automatic init_ctx(input int unsigned ctx);
    begin
      @(negedge clk);
      init_context = ctx[2:0];
      init_valid = 1'b1;
      if (!init_ready) fail("init was not ready");
      @(negedge clk);
      init_valid = 1'b0;
    end
  endtask

  task automatic drive_vectors(input int unsigned kv_row);
    begin
      for (int lane = 0; lane < D; lane++) begin
        q_row[lane] = '0;
        k_row[lane] = '0;
        v_row[lane] = (lane == kv_row) ? 16'sh0100 : 16'sh0000;
      end
    end
  endtask

  task automatic issue_score(
    input int unsigned ctx,
    input int unsigned kv_row,
    input bit last
  );
    begin
      drive_vectors(kv_row);
      @(negedge clk);
      while (!score_ready) @(negedge clk);
      score_context = ctx[2:0];
      q_index = ctx[7:0];
      k_index = kv_row[7:0];
      score_last = last;
      score_valid = 1'b1;
      @(negedge clk);
      score_valid = 1'b0;
      score_last = 1'b0;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    init_valid = 1'b0;
    init_context = '0;
    score_valid = 1'b0;
    score_context = '0;
    q_index = '0;
    k_index = '0;
    score_last = 1'b0;
    drive_vectors(0);

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    for (int ctx = 0; ctx < GROUP_ROWS; ctx++) begin
      init_ctx(ctx);
    end

    issue_score(3, 0, 1'b0);
    @(negedge clk);
    score_context = 3'd3;
    if (score_ready) fail("same context accepted a second score while pending");
    while (!context_done_valid || context_done != 3'd3) @(negedge clk);

    for (int ctx = 0; ctx < GROUP_ROWS; ctx++) begin
      for (int kv = 0; kv <= ctx; kv++) begin
        issue_score(ctx, kv, kv == ctx);
        while (!context_done_valid || context_done != ctx[2:0]) @(negedge clk);
      end
    end

    wait (final_count == GROUP_ROWS);
    repeat (4) @(negedge clk);
    $display("tb_group_engine_tile PASS");
    $finish;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      final_count <= 0;
    end else if (final_valid) begin
      if (div_zero) fail("finalize reported div_zero");
      if (final_context !== final_count[2:0]) begin
        $fatal(1, "final context mismatch got=%0d expected=%0d",
               final_context, final_count);
      end
      if (final_count == 0) begin
        if (final_row[0] <= 0) fail("context 0 final lane 0 was not positive");
        for (int lane = 1; lane < D; lane++) begin
          if (final_row[lane] !== '0) fail("context 0 one-hot final had non-zero side lane");
        end
      end
      final_count <= final_count + 1;
    end
  end

  initial begin
    #500000;
    fail("timeout");
  end
endmodule
