`timescale 1ns/1ps
`default_nettype none

module axi_lite_regs #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [ADDR_WIDTH-1:0]   s_awaddr,
    input  wire                    s_awvalid,
    output wire                    s_awready,
    input  wire [DATA_WIDTH-1:0]   s_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_wstrb,
    input  wire                    s_wvalid,
    output wire                    s_wready,
    output reg  [1:0]              s_bresp,
    output reg                     s_bvalid,
    input  wire                    s_bready,
    input  wire [ADDR_WIDTH-1:0]   s_araddr,
    input  wire                    s_arvalid,
    output wire                    s_arready,
    output reg  [DATA_WIDTH-1:0]   s_rdata,
    output reg  [1:0]              s_rresp,
    output reg                     s_rvalid,
    input  wire                    s_rready,

    output reg                     start_pulse,
    output reg                     soft_reset_pulse,
    output wire                    irq_enable,
    output wire                    irq_pending,
    output wire                    causal_enable,
    output wire [1:0]              format_sel,
    output wire [63:0]             q_base_addr,
    output wire [63:0]             k_base_addr,
    output wire [63:0]             v_base_addr,
    output wire [63:0]             o_base_addr,
    output wire [31:0]             stride_bytes,
    output wire [7:0]              valid_len,
    output wire [5:0]              seq_len,
    output wire [31:0]             neg_large,
    output wire [15:0]             score_scale,
    output wire                    task_chain_enable,
    output wire                    task_queue_not_empty,
    input  wire                    task_dequeue,
    input  wire                    task_busy,
    input  wire                    task_done,
    input  wire                    task_error,
    input  wire [31:0]             perf_read_data,
    output wire                    stream_en,
    output wire                    dropout_en,
    output wire [31:0]             dropout_seed,
    output wire [15:0]             dropout_prob,
    output wire [2:0]              num_heads,
    output wire [31:0]             head_stride
);

localparam [ADDR_WIDTH-1:0] REG_CTRL            = 12'h000;
localparam [ADDR_WIDTH-1:0] REG_STATUS          = 12'h004;
localparam [ADDR_WIDTH-1:0] REG_CFG             = 12'h008;
localparam [ADDR_WIDTH-1:0] REG_SEQ_LEN         = 12'h00C;
localparam [ADDR_WIDTH-1:0] REG_VALID_LEN       = 12'h010;
localparam [ADDR_WIDTH-1:0] REG_Q_LO            = 12'h014;
localparam [ADDR_WIDTH-1:0] REG_Q_HI            = 12'h018;
localparam [ADDR_WIDTH-1:0] REG_K_LO            = 12'h01c;
localparam [ADDR_WIDTH-1:0] REG_K_HI            = 12'h020;
localparam [ADDR_WIDTH-1:0] REG_V_LO            = 12'h024;
localparam [ADDR_WIDTH-1:0] REG_V_HI            = 12'h028;
localparam [ADDR_WIDTH-1:0] REG_O_LO            = 12'h02c;
localparam [ADDR_WIDTH-1:0] REG_O_HI            = 12'h030;
localparam [ADDR_WIDTH-1:0] REG_STRIDE          = 12'h034;
localparam [ADDR_WIDTH-1:0] REG_NEG_LARGE       = 12'h038;
localparam [ADDR_WIDTH-1:0] REG_SCALE           = 12'h03c;
localparam [ADDR_WIDTH-1:0] REG_CYCLES          = 12'h040;
localparam [ADDR_WIDTH-1:0] REG_TASK_PARAM_ADDR = 12'h044;
localparam [ADDR_WIDTH-1:0] REG_TASK_PARAM_DATA = 12'h048;
localparam [ADDR_WIDTH-1:0] REG_TASK_QUEUE_CTRL = 12'h04C;
    localparam [ADDR_WIDTH-1:0] REG_DROPOUT_SEED    = 12'h050;
    localparam [ADDR_WIDTH-1:0] REG_DROPOUT_PROB    = 12'h054;
    localparam [ADDR_WIDTH-1:0] REG_NUM_HEADS       = 12'h058;
    localparam [ADDR_WIDTH-1:0] REG_HEAD_STRIDE     = 12'h05C;

reg [ADDR_WIDTH-1:0] awaddr_reg;
reg                  aw_hold_reg;
reg [31:0]           cfg_reg;
reg [31:0]           q_lo_reg, q_hi_reg;
reg [31:0]           k_lo_reg, k_hi_reg;
reg [31:0]           v_lo_reg, v_hi_reg;
reg [31:0]           o_lo_reg, o_hi_reg;
reg [31:0]           stride_reg;
reg [7:0]            valid_len_reg;
reg [31:0]           neg_large_reg;
reg [31:0]           scale_reg;
reg [5:0]            seq_len_reg;
reg                  irq_en_reg;
reg                  done_latched_reg;
reg                  error_latched_reg;

// Task parameter RAM: 8 entries x 8 words (64 x 32-bit)
// Entry layout: word0=Q_LO, word1=Q_HI, word2=K_LO, word3=K_HI,
//               word4=V_LO, word5=V_HI, word6=O_LO, word7=O_HI
reg [31:0]           task_ram [0:63];
reg [2:0]            task_param_entry_reg;
reg [2:0]            task_param_word_reg;

// Task queue FIFO: 8 deep, stores 3-bit task entry indices
reg [2:0]            task_queue_mem [0:7];
reg [2:0]            task_queue_wr_ptr;
reg [2:0]            task_queue_rd_ptr;
reg [3:0]            task_queue_count;

// Active task-loaded parameters (muxed onto base address outputs)
reg                  task_active_reg;
reg [31:0]           task_q_lo, task_q_hi;
reg [31:0]           task_k_lo, task_k_hi;
reg [31:0]           task_v_lo, task_v_hi;
reg [31:0]           task_o_lo, task_o_hi;
    reg [31:0]           dropout_seed_reg;
    reg [15:0]           dropout_prob_reg;
    reg [2:0]            num_heads_reg;
    reg [31:0]           head_stride_reg;

wire write_fire;
wire read_fire;
integer byte_idx;

assign s_awready = !aw_hold_reg;
assign s_wready = aw_hold_reg && !s_bvalid;
assign write_fire = s_wvalid && s_wready;
assign s_arready = !s_rvalid;
assign read_fire = s_arvalid && s_arready;
assign irq_enable = irq_en_reg;
assign irq_pending = done_latched_reg || error_latched_reg;
assign causal_enable = cfg_reg[0];
assign format_sel = cfg_reg[2:1];
assign q_base_addr = task_active_reg ? {task_q_hi, task_q_lo} : {q_hi_reg, q_lo_reg};
assign k_base_addr = task_active_reg ? {task_k_hi, task_k_lo} : {k_hi_reg, k_lo_reg};
assign v_base_addr = task_active_reg ? {task_v_hi, task_v_lo} : {v_hi_reg, v_lo_reg};
assign o_base_addr = task_active_reg ? {task_o_hi, task_o_lo} : {o_hi_reg, o_lo_reg};
assign stride_bytes = stride_reg;
assign valid_len = valid_len_reg;
assign seq_len = seq_len_reg;
assign neg_large = neg_large_reg;
assign score_scale = scale_reg[15:0];
assign task_chain_enable = cfg_reg[3];
assign task_queue_not_empty = (task_queue_count != 4'd0);
    assign stream_en = cfg_reg[4];
    assign dropout_en = cfg_reg[5];
    assign dropout_seed = dropout_seed_reg;
    assign dropout_prob = dropout_prob_reg;
    assign num_heads = num_heads_reg;
    assign head_stride = head_stride_reg;

function [31:0] apply_wstrb;
    input [31:0] old_value;
    input [31:0] new_value;
    input [3:0]  strobe;
    integer bi;
    begin
        apply_wstrb = old_value;
        for (bi = 0; bi < 4; bi = bi + 1) begin
            if (strobe[bi])
                apply_wstrb[bi*8 +: 8] = new_value[bi*8 +: 8];
        end
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        aw_hold_reg <= 1'b0;
        awaddr_reg <= {ADDR_WIDTH{1'b0}};
        s_bvalid <= 1'b0;
        s_bresp <= 2'b00;
        s_rvalid <= 1'b0;
        s_rresp <= 2'b00;
        s_rdata <= 32'd0;
        start_pulse <= 1'b0;
        soft_reset_pulse <= 1'b0;
        irq_en_reg <= 1'b0;
        cfg_reg <= 32'd1;
        q_lo_reg <= 32'd0; q_hi_reg <= 32'd0;
        k_lo_reg <= 32'd0; k_hi_reg <= 32'd0;
        v_lo_reg <= 32'd0; v_hi_reg <= 32'd0;
        o_lo_reg <= 32'd0; o_hi_reg <= 32'd0;
        stride_reg <= 32'd128;
        valid_len_reg <= 8'd0;
        seq_len_reg <= 6'd32;
        neg_large_reg <= 32'hfff0_0000;
        scale_reg <= 32'h00002000;
        done_latched_reg <= 1'b0;
        error_latched_reg <= 1'b0;
        task_param_entry_reg <= 3'd0;
        task_param_word_reg <= 3'd0;
        task_queue_wr_ptr <= 3'd0;
        task_queue_rd_ptr <= 3'd0;
        task_queue_count <= 4'd0;
        task_active_reg <= 1'b0;
        task_q_lo <= 32'd0; task_q_hi <= 32'd0;
        task_k_lo <= 32'd0; task_k_hi <= 32'd0;
        task_v_lo <= 32'd0; task_v_hi <= 32'd0;
        task_o_lo <= 32'd0; task_o_hi <= 32'd0;
        dropout_seed_reg <= 32'd0;
        dropout_prob_reg <= 16'd0;
        num_heads_reg <= 3'd1;
        head_stride_reg <= 32'd0;
    end else begin
        start_pulse <= 1'b0;
        soft_reset_pulse <= 1'b0;
        if (task_done)
            done_latched_reg <= 1'b1;
        if (task_error)
            error_latched_reg <= 1'b1;

        // Task dequeue: load next task params from RAM
        if (task_dequeue && (task_queue_count != 4'd0)) begin
            task_q_lo <= task_ram[{3'd0, task_queue_mem[task_queue_rd_ptr]}];
            task_q_hi <= task_ram[{3'd1, task_queue_mem[task_queue_rd_ptr]}];
            task_k_lo <= task_ram[{3'd2, task_queue_mem[task_queue_rd_ptr]}];
            task_k_hi <= task_ram[{3'd3, task_queue_mem[task_queue_rd_ptr]}];
            task_v_lo <= task_ram[{3'd4, task_queue_mem[task_queue_rd_ptr]}];
            task_v_hi <= task_ram[{3'd5, task_queue_mem[task_queue_rd_ptr]}];
            task_o_lo <= task_ram[{3'd6, task_queue_mem[task_queue_rd_ptr]}];
            task_o_hi <= task_ram[{3'd7, task_queue_mem[task_queue_rd_ptr]}];
            task_queue_rd_ptr <= task_queue_rd_ptr + 3'd1;
            task_queue_count <= task_queue_count - 4'd1;
            task_active_reg <= 1'b1;
        end
        // Clear task_active on explicit (non-chained) start
        if (start_pulse)
            task_active_reg <= 1'b0;

        if (s_awvalid && s_awready) begin
            aw_hold_reg <= 1'b1;
            awaddr_reg <= s_awaddr;
        end
        if (write_fire) begin
            case (awaddr_reg)
                REG_CTRL: begin
                    start_pulse <= s_wdata[0] && !task_busy;
                    if (s_wstrb[0] && s_wdata[0]) begin
                        done_latched_reg <= 1'b0;
                        error_latched_reg <= 1'b0;
                    end
                    soft_reset_pulse <= s_wdata[1];
                    if (s_wstrb[0] && s_wdata[1]) begin
                        done_latched_reg <= 1'b0;
                        error_latched_reg <= 1'b0;
                    end
                    if (s_wstrb[0])
                        irq_en_reg <= s_wdata[2];
                end
                REG_STATUS: begin
                    if (s_wstrb[0] && s_wdata[1])
                        done_latched_reg <= 1'b0;
                    if (s_wstrb[0] && s_wdata[2])
                        error_latched_reg <= 1'b0;
                end
                REG_CFG: cfg_reg <= apply_wstrb(cfg_reg, s_wdata, s_wstrb);
                REG_VALID_LEN: if (s_wstrb[0]) valid_len_reg <= s_wdata[7:0];
                REG_SEQ_LEN: if (s_wstrb[0]) seq_len_reg <= s_wdata[5:0];
                REG_Q_LO: q_lo_reg <= apply_wstrb(q_lo_reg, s_wdata, s_wstrb);
                REG_Q_HI: q_hi_reg <= apply_wstrb(q_hi_reg, s_wdata, s_wstrb);
                REG_K_LO: k_lo_reg <= apply_wstrb(k_lo_reg, s_wdata, s_wstrb);
                REG_K_HI: k_hi_reg <= apply_wstrb(k_hi_reg, s_wdata, s_wstrb);
                REG_V_LO: v_lo_reg <= apply_wstrb(v_lo_reg, s_wdata, s_wstrb);
                REG_V_HI: v_hi_reg <= apply_wstrb(v_hi_reg, s_wdata, s_wstrb);
                REG_O_LO: o_lo_reg <= apply_wstrb(o_lo_reg, s_wdata, s_wstrb);
                REG_O_HI: o_hi_reg <= apply_wstrb(o_hi_reg, s_wdata, s_wstrb);
                REG_STRIDE: stride_reg <= apply_wstrb(stride_reg, s_wdata, s_wstrb);
                REG_NEG_LARGE: neg_large_reg <= apply_wstrb(neg_large_reg, s_wdata, s_wstrb);
                REG_SCALE: scale_reg <= apply_wstrb(scale_reg, s_wdata, s_wstrb);
                REG_TASK_PARAM_ADDR: if (s_wstrb[0]) begin
                    task_param_entry_reg <= s_wdata[2:0];
                    task_param_word_reg <= s_wdata[5:3];
                end
                REG_TASK_PARAM_DATA: begin
                    task_ram[{task_param_word_reg, task_param_entry_reg}] <=
                        apply_wstrb(task_ram[{task_param_word_reg, task_param_entry_reg}], s_wdata, s_wstrb);
                    task_param_word_reg <= task_param_word_reg + 3'd1;
                end
                REG_TASK_QUEUE_CTRL: begin
                    if (s_wstrb[0]) begin
                        if (s_wdata[0] && (task_queue_count < 4'd8)) begin
                            task_queue_mem[task_queue_wr_ptr] <= task_param_entry_reg;
                            task_queue_wr_ptr <= task_queue_wr_ptr + 3'd1;
                            task_queue_count <= task_queue_count + 4'd1;
                        end
                        if (s_wdata[1]) begin
                            task_queue_wr_ptr <= 3'd0;
                            task_queue_rd_ptr <= 3'd0;
                            task_queue_count <= 4'd0;
                        end
                    end
                end
                REG_DROPOUT_SEED: if (s_wstrb[0]) dropout_seed_reg <= s_wdata;
                REG_DROPOUT_PROB: if (s_wstrb[0]) dropout_prob_reg <= s_wdata[15:0];
                REG_NUM_HEADS: if (s_wstrb[0]) num_heads_reg <= s_wdata[2:0];
                REG_HEAD_STRIDE: head_stride_reg <= apply_wstrb(head_stride_reg, s_wdata, s_wstrb);
                default: begin end
            endcase
            s_bvalid <= 1'b1;
            s_bresp <= 2'b00;
            aw_hold_reg <= 1'b0;
        end else if (s_bvalid && s_bready) begin
            s_bvalid <= 1'b0;
        end

        if (read_fire) begin
            s_rvalid <= 1'b1;
            s_rresp <= 2'b00;
            case (s_araddr)
                REG_CTRL:            s_rdata <= {29'd0, irq_en_reg, 2'b00};
                REG_STATUS:          s_rdata <= {29'd0, error_latched_reg, done_latched_reg, task_busy};
                REG_CFG:             s_rdata <= cfg_reg;
                REG_VALID_LEN:       s_rdata <= {24'd0, valid_len_reg};
                REG_SEQ_LEN:         s_rdata <= {26'd0, seq_len_reg};
                REG_Q_LO:            s_rdata <= q_lo_reg;
                REG_Q_HI:            s_rdata <= q_hi_reg;
                REG_K_LO:            s_rdata <= k_lo_reg;
                REG_K_HI:            s_rdata <= k_hi_reg;
                REG_V_LO:            s_rdata <= v_lo_reg;
                REG_V_HI:            s_rdata <= v_hi_reg;
                REG_O_LO:            s_rdata <= o_lo_reg;
                REG_O_HI:            s_rdata <= o_hi_reg;
                REG_STRIDE:          s_rdata <= stride_reg;
                REG_NEG_LARGE:       s_rdata <= neg_large_reg;
                REG_SCALE:           s_rdata <= scale_reg;
                REG_CYCLES:          s_rdata <= perf_read_data;
                REG_TASK_PARAM_ADDR: s_rdata <= {26'd0, task_param_word_reg, task_param_entry_reg};
                REG_TASK_PARAM_DATA: s_rdata <= task_ram[{task_param_word_reg, task_param_entry_reg}];
                REG_TASK_QUEUE_CTRL: s_rdata <= {28'd0, task_queue_count};
                REG_DROPOUT_SEED:    s_rdata <= dropout_seed_reg;
                REG_DROPOUT_PROB:    s_rdata <= {16'd0, dropout_prob_reg};
                REG_NUM_HEADS:       s_rdata <= {29'd0, num_heads_reg};
                REG_HEAD_STRIDE:     s_rdata <= head_stride_reg;
                default:             s_rdata <= 32'd0;
            endcase
        end else if (s_rvalid && s_rready) begin
            s_rvalid <= 1'b0;
        end
    end
end

endmodule

`default_nettype wire
