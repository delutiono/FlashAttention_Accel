`timescale 1ns/1ps

module axi_mem_model #(
  parameter int unsigned ADDR_W                = 64,
  parameter int unsigned DATA_W                = 64,
  parameter int unsigned MEM_WORDS             = 4096,
  parameter int unsigned AR_READY_STALL_CYCLES = 0,
  parameter int unsigned AW_READY_STALL_CYCLES = 0,
  parameter int unsigned W_READY_STALL_CYCLES  = 0,
  parameter int unsigned R_VALID_DELAY_CYCLES  = 0,
  parameter int unsigned B_VALID_DELAY_CYCLES  = 0
) (
  input  logic                clk,
  input  logic                rst_n,

  input  logic [ADDR_W-1:0]   s_axi_araddr,
  input  logic [7:0]          s_axi_arlen,
  input  logic [2:0]          s_axi_arsize,
  input  logic [1:0]          s_axi_arburst,
  input  logic                s_axi_arvalid,
  output logic                s_axi_arready,
  output logic [DATA_W-1:0]   s_axi_rdata,
  output logic [1:0]          s_axi_rresp,
  output logic                s_axi_rlast,
  output logic                s_axi_rvalid,
  input  logic                s_axi_rready,

  input  logic [ADDR_W-1:0]   s_axi_awaddr,
  input  logic [7:0]          s_axi_awlen,
  input  logic [2:0]          s_axi_awsize,
  input  logic [1:0]          s_axi_awburst,
  input  logic                s_axi_awvalid,
  output logic                s_axi_awready,
  input  logic [DATA_W-1:0]   s_axi_wdata,
  input  logic [DATA_W/8-1:0] s_axi_wstrb,
  input  logic                s_axi_wlast,
  input  logic                s_axi_wvalid,
  output logic                s_axi_wready,
  output logic [1:0]          s_axi_bresp,
  output logic                s_axi_bvalid,
  input  logic                s_axi_bready
);
  localparam int unsigned STRB_W = DATA_W / 8;
  localparam int unsigned ADDR_LSB = $clog2(STRB_W);
  localparam logic [ADDR_W-1:0] ADDR_INCR = STRB_W;
  localparam logic [2:0] AXI_SIZE = $clog2(STRB_W);

  logic [DATA_W-1:0] mem [0:MEM_WORDS-1];

  logic              rd_active;
  logic [ADDR_W-1:0] rd_addr_q;
  logic [8:0]        rd_beats_q;
  logic [8:0]        rd_count_q;
  logic              rd_error_q;
  logic [31:0]       ar_ready_stall_count_q;
  logic [31:0]       r_valid_delay_count_q;

  logic              wr_active;
  logic [ADDR_W-1:0] wr_addr_q;
  logic [8:0]        wr_beats_q;
  logic [8:0]        wr_count_q;
  logic              wr_error_q;
  logic              wr_resp_pending_q;
  logic [1:0]        wr_resp_q;
  logic [31:0]       aw_ready_stall_count_q;
  logic [31:0]       w_ready_stall_count_q;
  logic [31:0]       b_valid_delay_count_q;

  function automatic logic addr_in_range(input logic [ADDR_W-1:0] addr);
    logic [ADDR_W-ADDR_LSB-1:0] word_addr;
    begin
      word_addr = addr[ADDR_W-1:ADDR_LSB];
      return (word_addr < MEM_WORDS);
    end
  endfunction

  function automatic logic [DATA_W-1:0] load_word(input logic [ADDR_W-1:0] addr);
    logic [ADDR_W-ADDR_LSB-1:0] word_addr;
    begin
      word_addr = addr[ADDR_W-1:ADDR_LSB];
      if (word_addr < MEM_WORDS) begin
        return mem[word_addr];
      end
      return '0;
    end
  endfunction

  task automatic write_word(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    logic [ADDR_W-ADDR_LSB-1:0] word_addr;
    begin
      word_addr = addr[ADDR_W-1:ADDR_LSB];
      if (word_addr < MEM_WORDS) begin
        mem[word_addr] = data;
      end
    end
  endtask

  task automatic read_word(
    input  logic [ADDR_W-1:0] addr,
    output logic [DATA_W-1:0] data
  );
    begin
      data = load_word(addr);
    end
  endtask

  genvar byte_idx;
  generate
    for (byte_idx = 0; byte_idx < STRB_W; byte_idx++) begin : gen_wr_bytes
      always_ff @(posedge clk) begin
        if (rst_n && s_axi_wvalid && s_axi_wready &&
            s_axi_wstrb[byte_idx] && addr_in_range(wr_addr_q)) begin
          mem[wr_addr_q[ADDR_W-1:ADDR_LSB]][(byte_idx * 8) +: 8] <=
              s_axi_wdata[(byte_idx * 8) +: 8];
        end
      end
    end
  endgenerate

  assign s_axi_arready = !rd_active &&
                         (ar_ready_stall_count_q >= AR_READY_STALL_CYCLES);
  assign s_axi_awready = !wr_active && !wr_resp_pending_q && !s_axi_bvalid &&
                         (aw_ready_stall_count_q >= AW_READY_STALL_CYCLES);
  assign s_axi_wready  = wr_active && !s_axi_bvalid &&
                         (w_ready_stall_count_q >= W_READY_STALL_CYCLES);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_active    <= 1'b0;
      rd_addr_q    <= '0;
      rd_beats_q   <= '0;
      rd_count_q   <= '0;
      rd_error_q   <= 1'b0;
      ar_ready_stall_count_q <= '0;
      r_valid_delay_count_q  <= '0;
      s_axi_rdata  <= '0;
      s_axi_rresp  <= 2'b00;
      s_axi_rlast  <= 1'b0;
      s_axi_rvalid <= 1'b0;
    end else begin
      if (!rd_active && s_axi_arvalid && !s_axi_arready) begin
        ar_ready_stall_count_q <= ar_ready_stall_count_q + 32'd1;
      end else if (!s_axi_arvalid || (s_axi_arvalid && s_axi_arready)) begin
        ar_ready_stall_count_q <= '0;
      end

      if (s_axi_arvalid && s_axi_arready) begin
        rd_active  <= 1'b1;
        rd_addr_q  <= s_axi_araddr;
        rd_beats_q <= {1'b0, s_axi_arlen} + 9'd1;
        rd_count_q <= '0;
        rd_error_q <= (s_axi_arsize != AXI_SIZE) || (s_axi_arburst != 2'b01);
        r_valid_delay_count_q <= '0;
      end

      if (!s_axi_rvalid && rd_active) begin
        if (r_valid_delay_count_q < R_VALID_DELAY_CYCLES) begin
          r_valid_delay_count_q <= r_valid_delay_count_q + 32'd1;
        end else begin
          s_axi_rdata  <= load_word(rd_addr_q);
          s_axi_rresp  <= (rd_error_q || !addr_in_range(rd_addr_q)) ? 2'b10 : 2'b00;
          s_axi_rlast  <= (rd_count_q == rd_beats_q - 9'd1);
          s_axi_rvalid <= 1'b1;
        end
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
        r_valid_delay_count_q <= '0;
        if (s_axi_rlast) begin
          rd_active <= 1'b0;
        end else begin
          rd_addr_q  <= rd_addr_q + ADDR_INCR;
          rd_count_q <= rd_count_q + 9'd1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_active    <= 1'b0;
      wr_addr_q    <= '0;
      wr_beats_q   <= '0;
      wr_count_q   <= '0;
      wr_error_q   <= 1'b0;
      wr_resp_pending_q <= 1'b0;
      wr_resp_q     <= 2'b00;
      aw_ready_stall_count_q <= '0;
      w_ready_stall_count_q  <= '0;
      b_valid_delay_count_q  <= '0;
      s_axi_bresp  <= 2'b00;
      s_axi_bvalid <= 1'b0;
    end else begin
      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (!wr_active && !wr_resp_pending_q && !s_axi_bvalid &&
          s_axi_awvalid && !s_axi_awready) begin
        aw_ready_stall_count_q <= aw_ready_stall_count_q + 32'd1;
      end else if (!s_axi_awvalid || (s_axi_awvalid && s_axi_awready)) begin
        aw_ready_stall_count_q <= '0;
      end

      if (wr_active && s_axi_wvalid && !s_axi_wready) begin
        w_ready_stall_count_q <= w_ready_stall_count_q + 32'd1;
      end else if (!s_axi_wvalid || (s_axi_wvalid && s_axi_wready)) begin
        w_ready_stall_count_q <= '0;
      end

      if (wr_resp_pending_q && !s_axi_bvalid) begin
        if (b_valid_delay_count_q < B_VALID_DELAY_CYCLES) begin
          b_valid_delay_count_q <= b_valid_delay_count_q + 32'd1;
        end else begin
          s_axi_bresp <= wr_resp_q;
          s_axi_bvalid <= 1'b1;
          wr_resp_pending_q <= 1'b0;
          b_valid_delay_count_q <= '0;
        end
      end

      if (s_axi_awvalid && s_axi_awready) begin
        wr_active  <= 1'b1;
        wr_addr_q  <= s_axi_awaddr;
        wr_beats_q <= {1'b0, s_axi_awlen} + 9'd1;
        wr_count_q <= '0;
        wr_error_q <= (s_axi_awsize != AXI_SIZE) || (s_axi_awburst != 2'b01);
      end

      if (s_axi_wvalid && s_axi_wready) begin
        wr_error_q <= wr_error_q ||
                      !addr_in_range(wr_addr_q) ||
                      (s_axi_wlast != (wr_count_q == wr_beats_q - 9'd1));
        if (wr_count_q == wr_beats_q - 9'd1) begin
          wr_active    <= 1'b0;
          wr_resp_q    <= (wr_error_q || !addr_in_range(wr_addr_q) ||
                           !s_axi_wlast) ? 2'b10 : 2'b00;
          if (B_VALID_DELAY_CYCLES == 0) begin
            s_axi_bresp  <= (wr_error_q || !addr_in_range(wr_addr_q) ||
                             !s_axi_wlast) ? 2'b10 : 2'b00;
            s_axi_bvalid <= 1'b1;
          end else begin
            wr_resp_pending_q <= 1'b1;
            b_valid_delay_count_q <= '0;
          end
        end else begin
          wr_addr_q  <= wr_addr_q + ADDR_INCR;
          wr_count_q <= wr_count_q + 9'd1;
        end
      end
    end
  end
endmodule
