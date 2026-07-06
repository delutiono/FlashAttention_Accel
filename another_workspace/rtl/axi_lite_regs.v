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
    output wire [63:0]             q_base_addr,
    output wire [63:0]             k_base_addr,
    output wire [63:0]             v_base_addr,
    output wire [63:0]             o_base_addr,
    output wire [31:0]             stride_bytes,
    output wire [31:0]             neg_large,
    output wire [15:0]             score_scale,
    input  wire                    task_busy,
    input  wire                    task_done,
    input  wire                    task_error,
    input  wire [31:0]             perf_read_data,

    output wire [1:0]              lowp_mode,
    output wire [5:0]              lowp_block_rows,
    output wire [63:0]             q_scale_base_addr,
    output wire [63:0]             k_scale_base_addr,
    output wire [63:0]             v_scale_base_addr,
    input  wire [5:0]              active_q_group,
    input  wire [5:0]              active_kv_tile,
    output wire [15:0]             lowp_q_scale,
    output wire [15:0]             lowp_k_scale,
    output wire [15:0]             lowp_v_scale
);

localparam [ADDR_WIDTH-1:0] REG_CTRL     = 12'h000;
localparam [ADDR_WIDTH-1:0] REG_STATUS   = 12'h004;
localparam [ADDR_WIDTH-1:0] REG_CFG      = 12'h008;
localparam [ADDR_WIDTH-1:0] REG_Q_LO     = 12'h014;
localparam [ADDR_WIDTH-1:0] REG_Q_HI     = 12'h018;
localparam [ADDR_WIDTH-1:0] REG_K_LO     = 12'h01c;
localparam [ADDR_WIDTH-1:0] REG_K_HI     = 12'h020;
localparam [ADDR_WIDTH-1:0] REG_V_LO     = 12'h024;
localparam [ADDR_WIDTH-1:0] REG_V_HI     = 12'h028;
localparam [ADDR_WIDTH-1:0] REG_O_LO     = 12'h02c;
localparam [ADDR_WIDTH-1:0] REG_O_HI     = 12'h030;
localparam [ADDR_WIDTH-1:0] REG_STRIDE   = 12'h034;
localparam [ADDR_WIDTH-1:0] REG_NEG_LARGE= 12'h038;
localparam [ADDR_WIDTH-1:0] REG_SCALE    = 12'h03c;
localparam [ADDR_WIDTH-1:0] REG_CYCLES   = 12'h040;
localparam [ADDR_WIDTH-1:0] REG_LOWP_CFG        = 12'h060;
localparam [ADDR_WIDTH-1:0] REG_Q_SCALE_LO      = 12'h064;
localparam [ADDR_WIDTH-1:0] REG_Q_SCALE_HI      = 12'h068;
localparam [ADDR_WIDTH-1:0] REG_K_SCALE_LO      = 12'h06C;
localparam [ADDR_WIDTH-1:0] REG_K_SCALE_HI      = 12'h070;
localparam [ADDR_WIDTH-1:0] REG_V_SCALE_LO      = 12'h074;
localparam [ADDR_WIDTH-1:0] REG_V_SCALE_HI      = 12'h078;
localparam [ADDR_WIDTH-1:0] REG_LOWP_SCALE_ADDR = 12'h07C;
localparam [ADDR_WIDTH-1:0] REG_LOWP_SCALE_DATA = 12'h080;

reg [ADDR_WIDTH-1:0] awaddr_reg;
reg                  aw_hold_reg;
reg [31:0]           cfg_reg;
reg [31:0]           q_lo_reg, q_hi_reg;
reg [31:0]           k_lo_reg, k_hi_reg;
reg [31:0]           v_lo_reg, v_hi_reg;
reg [31:0]           o_lo_reg, o_hi_reg;
reg [31:0]           stride_reg;
reg [31:0]           neg_large_reg;
reg [31:0]           scale_reg;
reg                  irq_en_reg;
reg                  done_latched_reg;
reg                  error_latched_reg;
reg [31:0]           lowp_cfg_reg;
reg [31:0]           q_scale_lo_reg, q_scale_hi_reg;
reg [31:0]           k_scale_lo_reg, k_scale_hi_reg;
reg [31:0]           v_scale_lo_reg, v_scale_hi_reg;
reg [7:0]            lowp_scale_addr_reg;
reg [15:0]           q_scale_ram [0:63];
reg [15:0]           k_scale_ram [0:63];
reg [15:0]           v_scale_ram [0:63];
integer scale_idx;

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
assign q_base_addr = {q_hi_reg, q_lo_reg};
assign k_base_addr = {k_hi_reg, k_lo_reg};
assign v_base_addr = {v_hi_reg, v_lo_reg};
assign o_base_addr = {o_hi_reg, o_lo_reg};
assign stride_bytes = stride_reg;
assign neg_large = neg_large_reg;
assign score_scale = scale_reg[15:0];
assign lowp_mode = lowp_cfg_reg[1:0];
assign lowp_block_rows = (lowp_cfg_reg[13:8] == 6'd0) ? 6'd8 : lowp_cfg_reg[13:8];
assign q_scale_base_addr = {q_scale_hi_reg, q_scale_lo_reg};
assign k_scale_base_addr = {k_scale_hi_reg, k_scale_lo_reg};
assign v_scale_base_addr = {v_scale_hi_reg, v_scale_lo_reg};
assign lowp_q_scale = q_scale_ram[active_q_group];
assign lowp_k_scale = k_scale_ram[active_kv_tile];
assign lowp_v_scale = v_scale_ram[active_kv_tile];

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
        neg_large_reg <= 32'hfff0_0000;
        scale_reg <= 32'h00002000;
        done_latched_reg <= 1'b0;
        error_latched_reg <= 1'b0;
        lowp_cfg_reg <= 32'd0;
        q_scale_lo_reg <= 32'd0; q_scale_hi_reg <= 32'd0;
        k_scale_lo_reg <= 32'd0; k_scale_hi_reg <= 32'd0;
        v_scale_lo_reg <= 32'd0; v_scale_hi_reg <= 32'd0;
        lowp_scale_addr_reg <= 8'd0;
        for (scale_idx = 0; scale_idx < 64; scale_idx = scale_idx + 1) begin
            q_scale_ram[scale_idx] <= 16'hffff;
            k_scale_ram[scale_idx] <= 16'hffff;
            v_scale_ram[scale_idx] <= 16'hffff;
        end
    end else begin
        start_pulse <= 1'b0;
        soft_reset_pulse <= 1'b0;
        if (task_done)
            done_latched_reg <= 1'b1;
        if (task_error)
            error_latched_reg <= 1'b1;
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
                REG_LOWP_CFG: lowp_cfg_reg <= apply_wstrb(lowp_cfg_reg, s_wdata, s_wstrb);
                REG_Q_SCALE_LO: q_scale_lo_reg <= apply_wstrb(q_scale_lo_reg, s_wdata, s_wstrb);
                REG_Q_SCALE_HI: q_scale_hi_reg <= apply_wstrb(q_scale_hi_reg, s_wdata, s_wstrb);
                REG_K_SCALE_LO: k_scale_lo_reg <= apply_wstrb(k_scale_lo_reg, s_wdata, s_wstrb);
                REG_K_SCALE_HI: k_scale_hi_reg <= apply_wstrb(k_scale_hi_reg, s_wdata, s_wstrb);
                REG_V_SCALE_LO: v_scale_lo_reg <= apply_wstrb(v_scale_lo_reg, s_wdata, s_wstrb);
                REG_V_SCALE_HI: v_scale_hi_reg <= apply_wstrb(v_scale_hi_reg, s_wdata, s_wstrb);
                REG_LOWP_SCALE_ADDR: if (s_wstrb[0]) lowp_scale_addr_reg <= s_wdata[7:0];
                REG_LOWP_SCALE_DATA: if (s_wstrb[0] || s_wstrb[1]) begin
                    case (lowp_scale_addr_reg[7:6])
                        2'd0: q_scale_ram[lowp_scale_addr_reg[5:0]] <= s_wdata[15:0];
                        2'd1: k_scale_ram[lowp_scale_addr_reg[5:0]] <= s_wdata[15:0];
                        2'd2: v_scale_ram[lowp_scale_addr_reg[5:0]] <= s_wdata[15:0];
                        default: begin end
                    endcase
                end
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
                REG_CTRL:   s_rdata <= {29'd0, irq_en_reg, 2'b00};
                REG_STATUS: s_rdata <= {29'd0, error_latched_reg, done_latched_reg, task_busy};
                REG_CFG:    s_rdata <= cfg_reg;
                REG_Q_LO:   s_rdata <= q_lo_reg;
                REG_Q_HI:   s_rdata <= q_hi_reg;
                REG_K_LO:   s_rdata <= k_lo_reg;
                REG_K_HI:   s_rdata <= k_hi_reg;
                REG_V_LO:   s_rdata <= v_lo_reg;
                REG_V_HI:   s_rdata <= v_hi_reg;
                REG_O_LO:   s_rdata <= o_lo_reg;
                REG_O_HI:   s_rdata <= o_hi_reg;
                REG_STRIDE: s_rdata <= stride_reg;
                REG_NEG_LARGE: s_rdata <= neg_large_reg;
                REG_SCALE:  s_rdata <= scale_reg;
                REG_CYCLES: s_rdata <= perf_read_data;
                REG_LOWP_CFG:        s_rdata <= lowp_cfg_reg;
                REG_Q_SCALE_LO:      s_rdata <= q_scale_lo_reg;
                REG_Q_SCALE_HI:      s_rdata <= q_scale_hi_reg;
                REG_K_SCALE_LO:      s_rdata <= k_scale_lo_reg;
                REG_K_SCALE_HI:      s_rdata <= k_scale_hi_reg;
                REG_V_SCALE_LO:      s_rdata <= v_scale_lo_reg;
                REG_V_SCALE_HI:      s_rdata <= v_scale_hi_reg;
                REG_LOWP_SCALE_ADDR: s_rdata <= {24'd0, lowp_scale_addr_reg};
                REG_LOWP_SCALE_DATA: begin
                    case (lowp_scale_addr_reg[7:6])
                        2'd0: s_rdata <= {16'd0, q_scale_ram[lowp_scale_addr_reg[5:0]]};
                        2'd1: s_rdata <= {16'd0, k_scale_ram[lowp_scale_addr_reg[5:0]]};
                        2'd2: s_rdata <= {16'd0, v_scale_ram[lowp_scale_addr_reg[5:0]]};
                        default: s_rdata <= 32'd0;
                    endcase
                end
                default:    s_rdata <= 32'd0;
            endcase
        end else if (s_rvalid && s_rready) begin
            s_rvalid <= 1'b0;
        end
    end
end

endmodule

`default_nettype wire
