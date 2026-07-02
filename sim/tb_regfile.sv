`timescale 1ns/1ps

import fa_pkg::*;

module tb_regfile;
  logic clk;
  logic rst_n;

  logic [11:0] awaddr;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  logic [11:0] araddr;
  logic        arvalid;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  logic        start_pulse;
  logic        soft_reset_pulse;
  logic        done_clear_pulse;
  logic        irq_en;
  logic        causal_en;
  logic        compute_smoke_en;
  logic [63:0] q_base;
  logic [63:0] k_base;
  logic [63:0] v_base;
  logic [63:0] o_base;
  logic [31:0] stride_bytes;
  logic [15:0] neg_large;
  logic [15:0] scale;
  logic [31:0] cycles_i;
  logic        busy_i;
  logic        done_i;
  logic        error_i;

  fa_regfile dut (
    .clk,
    .rst_n,
    .s_axil_awaddr(awaddr),
    .s_axil_awvalid(awvalid),
    .s_axil_awready(awready),
    .s_axil_wdata(wdata),
    .s_axil_wstrb(wstrb),
    .s_axil_wvalid(wvalid),
    .s_axil_wready(wready),
    .s_axil_bresp(bresp),
    .s_axil_bvalid(bvalid),
    .s_axil_bready(bready),
    .s_axil_araddr(araddr),
    .s_axil_arvalid(arvalid),
    .s_axil_arready(arready),
    .s_axil_rdata(rdata),
    .s_axil_rresp(rresp),
    .s_axil_rvalid(rvalid),
    .s_axil_rready(rready),
    .start_pulse,
    .soft_reset_pulse,
    .done_clear_pulse,
    .irq_en,
    .causal_en,
    .compute_smoke_en,
    .q_base,
    .k_base,
    .v_base,
    .o_base,
    .stride_bytes,
    .neg_large,
    .scale,
    .cycles_i,
    .busy_i,
    .done_i,
    .error_i
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic axil_write(input logic [11:0] addr, input logic [31:0] data,
                            input logic [3:0] strb = 4'hf);
    begin
      @(negedge clk);
      awaddr  = addr;
      awvalid = 1'b1;
      wdata   = data;
      wstrb   = strb;
      wvalid  = 1'b1;
      bready  = 1'b1;
      wait (awready && wready);
      @(negedge clk);
      awvalid = 1'b0;
      wvalid  = 1'b0;
      wait (bvalid);
      @(negedge clk);
      bready  = 1'b0;
    end
  endtask

  task automatic axil_read(input logic [11:0] addr, output logic [31:0] data);
    begin
      @(negedge clk);
      araddr  = addr;
      arvalid = 1'b1;
      rready  = 1'b1;
      wait (arready);
      @(negedge clk);
      arvalid = 1'b0;
      wait (rvalid);
      data = rdata;
      @(negedge clk);
      rready  = 1'b0;
    end
  endtask

  task automatic expect_eq(input string name, input logic [31:0] got,
                           input logic [31:0] exp);
    begin
      if (got !== exp) begin
        $error("%s got 0x%08x expected 0x%08x", name, got, exp);
        $fatal(1);
      end
    end
  endtask

  integer protocol_errors;

  task automatic protocol_expect(input string name, input logic condition);
    begin
      if (!condition) begin
        $error("PROTOCOL: %s", name);
        protocol_errors = protocol_errors + 1;
      end
    end
  endtask

  task automatic reset_dut;
    begin
      rst_n   = 1'b0;
      awvalid = 1'b0;
      wvalid  = 1'b0;
      bready  = 1'b0;
      arvalid = 1'b0;
      rready  = 1'b0;
      repeat (3) @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(negedge clk);
    end
  endtask

  task automatic test_aw_before_w;
    integer wait_cycles;
    begin
      $display("TEST: AW handshake before W handshake");
      reset_dut();

      @(negedge clk);
      awaddr  = REG_CFG;
      awvalid = 1'b1;
      #1;
      protocol_expect("AW-first address was not accepted", awready);
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0;

      repeat (2) @(negedge clk);
      wdata  = 32'h0000_0000;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      #1;
      protocol_expect("AW-first data was not accepted", wready);
      @(posedge clk);
      @(negedge clk);
      wvalid = 1'b0;

      wait_cycles = 0;
      while (!bvalid && wait_cycles < 4) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
      end
      protocol_expect("AW-first write produced no B response", bvalid);
      protocol_expect("AW-first write did not update CFG", causal_en === 1'b0);
      if (bvalid) begin
        bready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        bready = 1'b0;
      end
    end
  endtask

  task automatic test_w_before_aw;
    integer wait_cycles;
    begin
      $display("TEST: W handshake before AW handshake");
      reset_dut();

      @(negedge clk);
      wdata  = 32'h0000_0000;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      #1;
      protocol_expect("W-first data was not accepted", wready);
      @(posedge clk);
      @(negedge clk);
      wvalid = 1'b0;

      repeat (2) @(negedge clk);
      awaddr  = REG_CFG;
      awvalid = 1'b1;
      #1;
      protocol_expect("W-first address was not accepted", awready);
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0;

      wait_cycles = 0;
      while (!bvalid && wait_cycles < 4) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
      end
      protocol_expect("W-first write produced no B response", bvalid);
      protocol_expect("W-first write did not update CFG", causal_en === 1'b0);
      if (bvalid) begin
        bready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        bready = 1'b0;
      end
    end
  endtask

  task automatic test_no_repeat_under_b_backpressure;
    integer pulse_count;
    integer cycle_count;
    begin
      $display("TEST: no repeated write while B is backpressured");
      reset_dut();
      pulse_count = 0;

      @(negedge clk);
      awaddr  = REG_CTRL;
      awvalid = 1'b1;
      wdata   = 32'h0000_0001;
      wstrb   = 4'hf;
      wvalid  = 1'b1;
      bready  = 1'b0;

      for (cycle_count = 0; cycle_count < 6; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
        if (start_pulse) pulse_count = pulse_count + 1;
      end
      protocol_expect("backpressured write did not raise BVALID", bvalid);
      protocol_expect("backpressured write committed more than once",
                      pulse_count == 1);

      @(negedge clk);
      awvalid = 1'b0;
      wvalid  = 1'b0;
      bready  = 1'b1;
      @(posedge clk);
      @(negedge clk);
      bready = 1'b0;
    end
  endtask

  task automatic consume_b_response;
    begin
      if (bvalid) begin
        @(negedge clk);
        bready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        bready = 1'b0;
      end
    end
  endtask

  task automatic test_incomplete_write_has_no_effect;
    integer cycle_count;
    begin
      $display("TEST: incomplete AW-only/W-only writes have no effect");
      reset_dut();

      @(negedge clk);
      awaddr  = REG_CTRL;
      awvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0;
      for (cycle_count = 0; cycle_count < 4; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
        protocol_expect("AW-only write raised BVALID", !bvalid);
        protocol_expect("AW-only write caused START pulse", !start_pulse);
        protocol_expect("AW-only write changed IRQ enable", !irq_en);
      end

      reset_dut();
      @(negedge clk);
      wdata  = 32'h0000_0005;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      wvalid = 1'b0;
      for (cycle_count = 0; cycle_count < 4; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
        protocol_expect("W-only write raised BVALID", !bvalid);
        protocol_expect("W-only write caused START pulse", !start_pulse);
        protocol_expect("W-only write changed IRQ enable", !irq_en);
      end
    end
  endtask

  task automatic test_held_valid_captured_once;
    integer aw_handshakes;
    integer w_handshakes;
    integer start_count;
    integer cycle_count;
    begin
      $display("TEST: held AWVALID/WVALID are captured once");
      reset_dut();
      aw_handshakes = 0;
      w_handshakes  = 0;
      start_count   = 0;

      @(negedge clk);
      awaddr  = REG_CTRL;
      awvalid = 1'b1;
      for (cycle_count = 0; cycle_count < 4; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        if (awvalid && awready) aw_handshakes = aw_handshakes + 1;
        if (wvalid && wready) w_handshakes = w_handshakes + 1;
        #1;
        if (start_pulse) start_count = start_count + 1;
      end

      @(negedge clk);
      wdata  = 32'h0000_0001;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      for (cycle_count = 0; cycle_count < 5; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        if (awvalid && awready) aw_handshakes = aw_handshakes + 1;
        if (wvalid && wready) w_handshakes = w_handshakes + 1;
        #1;
        if (start_pulse) start_count = start_count + 1;
      end

      protocol_expect("held AWVALID handshook more than once",
                      aw_handshakes == 1);
      protocol_expect("held WVALID handshook more than once",
                      w_handshakes == 1);
      protocol_expect("held valids committed START more than once",
                      start_count == 1);
      protocol_expect("held valids produced no B response", bvalid);

      @(negedge clk);
      awvalid = 1'b0;
      wvalid  = 1'b0;
      consume_b_response();
    end
  endtask

  task automatic test_reset_clears_half_write;
    integer cycle_count;
    begin
      $display("TEST: reset clears half-completed writes");
      reset_dut();

      @(negedge clk);
      awaddr  = REG_CTRL;
      awvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0;
      rst_n   = 1'b0;
      repeat (2) @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(negedge clk);

      wdata  = 32'h0000_0005;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      wvalid = 1'b0;
      for (cycle_count = 0; cycle_count < 3; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
        protocol_expect("pre-reset AW paired with post-reset W", !bvalid);
        protocol_expect("pre-reset AW caused post-reset START", !start_pulse);
        protocol_expect("pre-reset AW changed post-reset IRQ", !irq_en);
      end

      reset_dut();
      @(negedge clk);
      wdata  = 32'h0000_0005;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      wvalid = 1'b0;
      rst_n  = 1'b0;
      repeat (2) @(negedge clk);
      rst_n = 1'b1;
      repeat (2) @(negedge clk);

      awaddr  = REG_CTRL;
      awvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0;
      for (cycle_count = 0; cycle_count < 3; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
        protocol_expect("pre-reset W paired with post-reset AW", !bvalid);
        protocol_expect("pre-reset W caused post-reset START", !start_pulse);
        protocol_expect("pre-reset W changed post-reset IRQ", !irq_en);
      end
    end
  endtask

  task automatic test_separated_write_semantics;
    integer pulse_count;
    integer cycle_count;
    begin
      $display("TEST: separated handshakes preserve WSTRB and pulse semantics");
      reset_dut();

      @(negedge clk);
      awaddr  = REG_Q_BASE_L;
      awvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0;
      repeat (2) @(negedge clk);
      wdata  = 32'haabb_ccdd;
      wstrb  = 4'b0101;
      wvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      wvalid = 1'b0;
      repeat (2) @(posedge clk);
      #1;
      protocol_expect("separated WSTRB write produced no B response", bvalid);
      protocol_expect("separated WSTRB bytes were not preserved",
                      q_base[31:0] === 32'h00bb_00dd);
      consume_b_response();

      reset_dut();
      pulse_count = 0;
      @(negedge clk);
      wdata  = 32'h0000_0001;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      wvalid = 1'b0;
      repeat (2) @(negedge clk);
      awaddr  = REG_CTRL;
      awvalid = 1'b1;
      @(posedge clk);
      #1;
      if (start_pulse) pulse_count = pulse_count + 1;
      @(negedge clk);
      awvalid = 1'b0;
      for (cycle_count = 0; cycle_count < 3; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
        if (start_pulse) pulse_count = pulse_count + 1;
      end
      protocol_expect("separated START did not pulse exactly once",
                      pulse_count == 1);
      protocol_expect("separated START produced no B response", bvalid);
      consume_b_response();

      reset_dut();
      done_i = 1'b1;
      pulse_count = 0;
      @(negedge clk);
      awaddr  = REG_STATUS;
      awvalid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      awvalid = 1'b0;
      repeat (2) @(negedge clk);
      wdata  = 32'h0000_0002;
      wstrb  = 4'hf;
      wvalid = 1'b1;
      @(posedge clk);
      #1;
      if (done_clear_pulse) pulse_count = pulse_count + 1;
      @(negedge clk);
      wvalid = 1'b0;
      for (cycle_count = 0; cycle_count < 3; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
        if (done_clear_pulse) pulse_count = pulse_count + 1;
      end
      protocol_expect("separated DONE W1C did not pulse exactly once",
                      pulse_count == 1);
      protocol_expect("separated DONE W1C produced no B response", bvalid);
      consume_b_response();
      done_i = 1'b0;
    end
  endtask

  logic [31:0] rd;

  initial begin
    protocol_errors = 0;
    rst_n = 1'b0;
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = 4'h0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b0;
    cycles_i = 32'h1234_5678;
    busy_i = 1'b0;
    done_i = 1'b0;
    error_i = 1'b0;

    test_aw_before_w();
    test_w_before_aw();
    test_no_repeat_under_b_backpressure();
    test_incomplete_write_has_no_effect();
    test_held_valid_captured_once();
    test_reset_clears_half_write();
    test_separated_write_semantics();
    if (protocol_errors != 0) begin
      $fatal(1, "AXI4-Lite protocol regression failures: %0d",
             protocol_errors);
    end

    reset_dut();

    axil_read(REG_CFG, rd);
    expect_eq("default CFG", rd, 32'h0000_0001);
    axil_read(REG_STRIDE_BYTES, rd);
    expect_eq("default stride", rd, 32'd128);
    axil_read(REG_NEG_LARGE, rd);
    expect_eq("default neg_large", rd, 32'h0000_8000);
    axil_read(REG_SCALE, rd);
    expect_eq("default scale", rd, 32'd32);

    axil_write(REG_Q_BASE_L, 32'h1122_3344);
    axil_write(REG_Q_BASE_H, 32'h5566_7788);
    if (q_base !== 64'h5566_7788_1122_3344) begin
      $fatal(1, "q_base mismatch: 0x%016x", q_base);
    end

    axil_write(REG_CFG, 32'h0000_0000, 4'h0);
    axil_read(REG_CFG, rd);
    expect_eq("WSTRB zero keeps CFG", rd, 32'h0000_0001);

    @(negedge clk);
    awaddr  = REG_CTRL;
    awvalid = 1'b1;
    wdata   = 32'h0000_0005;
    wstrb   = 4'hf;
    wvalid  = 1'b1;
    bready  = 1'b1;
    @(posedge clk);
    #1;
    if (!start_pulse || !irq_en) begin
      $fatal(1, "CTRL did not produce start_pulse and irq_en");
    end
    @(negedge clk);
    awvalid = 1'b0;
    wvalid  = 1'b0;
    @(posedge clk);
    #1;
    bready  = 1'b0;
    if (start_pulse) begin
      $fatal(1, "start_pulse must self clear");
    end

    done_i = 1'b1;
    axil_read(REG_STATUS, rd);
    expect_eq("STATUS done", rd, 32'h0000_0002);
    @(negedge clk);
    awaddr  = REG_STATUS;
    awvalid = 1'b1;
    wdata   = 32'h0000_0002;
    wstrb   = 4'hf;
    wvalid  = 1'b1;
    bready  = 1'b1;
    @(posedge clk);
    #1;
    if (!done_clear_pulse) begin
      $fatal(1, "STATUS W1C did not pulse done_clear");
    end
    @(negedge clk);
    awvalid = 1'b0;
    wvalid  = 1'b0;
    @(posedge clk);
    #1;
    bready  = 1'b0;

    axil_read(REG_CYCLES, rd);
    expect_eq("CYCLES", rd, cycles_i);

    $display("tb_regfile PASS");
    $finish;
  end
endmodule
