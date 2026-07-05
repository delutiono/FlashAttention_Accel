`timescale 1ns/1ps

module axi_mem_model_128 #(
  parameter int unsigned ADDR_W    = 64,
  parameter int unsigned MEM_WORDS = 16384
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic [ADDR_W-1:0] s_axi_araddr,
  input  logic [7:0]        s_axi_arlen,
  input  logic [2:0]        s_axi_arsize,
  input  logic [1:0]        s_axi_arburst,
  input  logic              s_axi_arvalid,
  output logic              s_axi_arready,
  output logic [127:0]      s_axi_rdata,
  output logic [1:0]        s_axi_rresp,
  output logic              s_axi_rlast,
  output logic              s_axi_rvalid,
  input  logic              s_axi_rready,

  input  logic [ADDR_W-1:0] s_axi_awaddr,
  input  logic [7:0]        s_axi_awlen,
  input  logic [2:0]        s_axi_awsize,
  input  logic [1:0]        s_axi_awburst,
  input  logic              s_axi_awvalid,
  output logic              s_axi_awready,
  input  logic [127:0]      s_axi_wdata,
  input  logic [15:0]       s_axi_wstrb,
  input  logic              s_axi_wlast,
  input  logic              s_axi_wvalid,
  output logic              s_axi_wready,
  output logic [1:0]        s_axi_bresp,
  output logic              s_axi_bvalid,
  input  logic              s_axi_bready
);
  localparam int unsigned STRB_W = 16;
  localparam int unsigned ADDR_LSB = 4;
  localparam logic [ADDR_W-1:0] ADDR_INCR = 64'd16;

  logic [127:0] mem [0:MEM_WORDS-1];
  logic rd_active;
  logic rd_accept_visible_q;
  logic [1:0] rd_latency_q;
  logic [ADDR_W-1:0] rd_addr_q;
  logic [8:0] rd_beats_q;
  logic [8:0] rd_count_q;
  logic rd_error_q;

  logic wr_active;
  logic wr_accept_visible_q;
  logic [ADDR_W-1:0] wr_addr_q;
  logic [8:0] wr_beats_q;
  logic [8:0] wr_count_q;
  logic wr_error_q;
  logic wr_seen_wlast_q;
  logic wr_resp_pending_q;
  logic wr_bvisible_q;

  integer init_idx;
  initial begin
    for (init_idx = 0; init_idx < MEM_WORDS; init_idx = init_idx + 1) begin
      mem[init_idx] = 128'd0;
    end
  end

  function automatic logic addr_in_range(input logic [ADDR_W-1:0] addr);
    logic [ADDR_W-ADDR_LSB-1:0] word_addr;
    begin
      word_addr = addr[ADDR_W-1:ADDR_LSB];
      return word_addr < MEM_WORDS;
    end
  endfunction

  wire wr_hs = !wr_accept_visible_q && s_axi_wvalid && s_axi_wready;
  wire wr_last_expected = (wr_count_q == wr_beats_q - 9'd1);
  wire wr_final_hs = wr_hs && wr_last_expected && (s_axi_wlast || wr_seen_wlast_q);
  wire wr_next_error = wr_error_q ||
                       !addr_in_range(wr_addr_q);

  function automatic logic [127:0] load_word(input logic [ADDR_W-1:0] addr);
    logic [ADDR_W-ADDR_LSB-1:0] word_addr;
    begin
      word_addr = addr[ADDR_W-1:ADDR_LSB];
      if (word_addr < MEM_WORDS) begin
        return mem[word_addr];
      end
      return 128'd0;
    end
  endfunction

  task automatic read_word(
    input  logic [ADDR_W-1:0] addr,
    output logic [127:0] data
  );
    begin
      data = load_word(addr);
    end
  endtask

  task automatic write_word(
    input logic [ADDR_W-1:0] addr,
    input logic [127:0] data
  );
    logic [ADDR_W-ADDR_LSB-1:0] word_addr;
    begin
      word_addr = addr[ADDR_W-1:ADDR_LSB];
      if (word_addr < MEM_WORDS) begin
        mem[word_addr] = data;
      end
    end
  endtask

  genvar byte_idx;
  generate
    for (byte_idx = 0; byte_idx < STRB_W; byte_idx = byte_idx + 1) begin : g_wr_byte
      always @(posedge clk) begin
        if (rst_n && s_axi_wvalid && s_axi_wready &&
            s_axi_wstrb[byte_idx] && addr_in_range(wr_addr_q)) begin
          mem[wr_addr_q[ADDR_W-1:ADDR_LSB]][byte_idx*8 +: 8] <=
              s_axi_wdata[byte_idx*8 +: 8];
        end
      end
    end
  endgenerate

  // Keep ARREADY visible for one full cycle after accepting an address. This
  // avoids gate-level zero-delay delta-cycle races where the testbench slave
  // can otherwise appear to return R data before the DUT observes AR.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_active <= 1'b0;
      rd_accept_visible_q <= 1'b0;
      rd_latency_q <= 2'd0;
      rd_addr_q <= '0;
      rd_beats_q <= '0;
      rd_count_q <= '0;
      rd_error_q <= 1'b0;
      s_axi_arready <= 1'b1;
      s_axi_rdata <= 128'd0;
      s_axi_rresp <= 2'b00;
      s_axi_rlast <= 1'b0;
      s_axi_rvalid <= 1'b0;
    end else begin
      if (rd_accept_visible_q) begin
        rd_accept_visible_q <= 1'b0;
        s_axi_arready <= 1'b0;
      end

      if (!rd_active && !rd_accept_visible_q && s_axi_arvalid && s_axi_arready) begin
        rd_active <= 1'b1;
        rd_accept_visible_q <= 1'b1;
        rd_latency_q <= 2'd2;
        rd_addr_q <= s_axi_araddr;
        rd_beats_q <= {1'b0, s_axi_arlen} + 9'd1;
        rd_count_q <= 9'd0;
        rd_error_q <= (s_axi_arsize != 3'd4) || (s_axi_arburst != 2'b01);
        s_axi_arready <= 1'b1;
      end

      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
        if (s_axi_rlast) begin
          rd_active <= 1'b0;
          rd_accept_visible_q <= 1'b0;
          s_axi_arready <= 1'b1;
        end else begin
          rd_addr_q <= rd_addr_q + ADDR_INCR;
          rd_count_q <= rd_count_q + 9'd1;
        end
      end else if (rd_active && !s_axi_rvalid && (rd_latency_q != 2'd0)) begin
        rd_latency_q <= rd_latency_q - 2'd1;
      end else if (!s_axi_rvalid && rd_active && !rd_accept_visible_q) begin
        s_axi_rdata <= load_word(rd_addr_q);
        s_axi_rresp <= (rd_error_q || !addr_in_range(rd_addr_q)) ? 2'b10 : 2'b00;
        s_axi_rlast <= (rd_count_q == rd_beats_q - 9'd1);
        s_axi_rvalid <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_active <= 1'b0;
      wr_accept_visible_q <= 1'b0;
      wr_addr_q <= '0;
      wr_beats_q <= '0;
      wr_count_q <= '0;
      wr_error_q <= 1'b0;
      wr_seen_wlast_q <= 1'b0;
      wr_resp_pending_q <= 1'b0;
      wr_bvisible_q <= 1'b0;
      s_axi_awready <= 1'b1;
      s_axi_wready <= 1'b0;
      s_axi_bresp <= 2'b00;
      s_axi_bvalid <= 1'b0;
    end else begin
      if (s_axi_bvalid && (s_axi_bready || wr_bvisible_q)) begin
`ifdef FA_GATE_TRACE
        $display("MEMTRACE b_clear t=%0t bresp=%0b bready=%0b auto=%0b",
                 $time, s_axi_bresp, s_axi_bready, wr_bvisible_q && !s_axi_bready);
`endif
        s_axi_bvalid <= 1'b0;
        wr_bvisible_q <= 1'b0;
        s_axi_awready <= 1'b1;
      end

      if (wr_resp_pending_q && !s_axi_bvalid) begin
`ifdef FA_GATE_TRACE
        $display("MEMTRACE b_issue t=%0t bresp=%0b", $time, s_axi_bresp);
`endif
        wr_resp_pending_q <= 1'b0;
        s_axi_bvalid <= 1'b1;
        wr_bvisible_q <= 1'b1;
      end

      if (wr_accept_visible_q) begin
        wr_accept_visible_q <= 1'b0;
        s_axi_awready <= 1'b0;
        s_axi_wready <= 1'b1;
      end

      if (!wr_active && !wr_accept_visible_q && !wr_resp_pending_q && !s_axi_bvalid &&
          s_axi_awvalid && s_axi_awready) begin
        wr_active <= 1'b1;
        wr_accept_visible_q <= 1'b1;
        wr_addr_q <= s_axi_awaddr;
        wr_beats_q <= {1'b0, s_axi_awlen} + 9'd1;
        wr_count_q <= 9'd0;
        wr_error_q <= (s_axi_awsize != 3'd4) || (s_axi_awburst != 2'b01);
        wr_seen_wlast_q <= 1'b0;
        s_axi_awready <= 1'b1;
        s_axi_wready <= 1'b0;
      end

      if (wr_hs) begin
        wr_error_q <= wr_next_error;
`ifdef FA_GATE_TRACE
        if (wr_last_expected || s_axi_wlast) begin
          $display("MEMTRACE wr_hs t=%0t count=%0d beats=%0d wlast=%0b seen_wlast=%0b final=%0b bvalid=%0b bready=%0b",
                   $time, wr_count_q, wr_beats_q, s_axi_wlast, wr_seen_wlast_q,
                   wr_final_hs, s_axi_bvalid, s_axi_bready);
        end
`endif
        if (wr_final_hs) begin
          wr_active <= 1'b0;
          wr_accept_visible_q <= 1'b0;
          wr_seen_wlast_q <= 1'b0;
          s_axi_wready <= 1'b0;
          s_axi_bresp <= wr_next_error ? 2'b10 : 2'b00;
          wr_resp_pending_q <= 1'b1;
        end else begin
          s_axi_wready <= 1'b1;
          if (s_axi_wlast) begin
            wr_seen_wlast_q <= 1'b1;
          end
          if (!wr_last_expected) begin
            wr_addr_q <= wr_addr_q + ADDR_INCR;
            wr_count_q <= wr_count_q + 9'd1;
          end
        end
      end
    end
  end
endmodule
