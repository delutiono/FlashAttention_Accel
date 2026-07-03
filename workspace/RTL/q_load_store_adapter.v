`timescale 1ns/1ps
`default_nettype none

module q_load_store_adapter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         q_load_start,
    input  wire         q_load_page,
    output reg          q_load_done,
    input  wire         q_rd_valid,
    output wire         q_rd_ready,
    input  wire [127:0] q_rd_data,
    input  wire         q_rd_last,
    input  wire         o_store_start,
    input  wire         o_store_page,
    output wire         o_store_busy,
    output wire         o_store_done,
    output wire         o_wr_valid,
    input  wire         o_wr_ready,
    output wire [127:0] o_wr_data,
    output wire [15:0]  o_wr_strb,
    output wire         o_wr_last,
    input  wire         fin_valid,
    output wire         fin_ready,
    input  wire         fin_page,
    input  wire [2:0]   fin_row,
    input  wire         fin_half,
    input  wire [1:0]   fin_pair,
    input  wire [127:0] fin_data,
    output reg          q_rw_valid,
    output reg          q_rw_write,
    output reg  [1:0]   q_rw_pair,
    output reg  [4:0]   q_rw_addr,
    output reg  [15:0]  q_rw_wmask,
    output reg  [127:0] q_rw_wdata,
    input  wire         q_rw_rvalid,
    input  wire [127:0] q_rw_rdata
);

reg q_load_busy_reg;
reg [5:0] q_load_count_reg;
wire q_load_fire = q_rd_valid && q_rd_ready;
wire store_q_valid;
wire store_q_write;
wire [1:0] store_q_pair;
wire [4:0] store_q_addr;

assign q_rd_ready = q_load_busy_reg;
assign fin_ready = !q_load_busy_reg && !o_store_busy;

o_store_adapter u_store (
    .clk(clk), .rst_n(rst_n), .start(o_store_start), .page(o_store_page),
    .busy(o_store_busy), .done(o_store_done),
    .q_rw_valid(store_q_valid), .q_rw_write(store_q_write),
    .q_rw_pair(store_q_pair), .q_rw_addr(store_q_addr),
    .q_rw_rvalid(q_rw_rvalid), .q_rw_rdata(q_rw_rdata),
    .wr_valid(o_wr_valid), .wr_ready(o_wr_ready), .wr_data(o_wr_data),
    .wr_strb(o_wr_strb), .wr_last(o_wr_last)
);

always @(posedge clk) begin
    if (!rst_n) begin
        q_load_busy_reg <= 1'b0;
        q_load_done <= 1'b0;
        q_load_count_reg <= 6'd0;
        q_rw_valid <= 1'b0;
        q_rw_write <= 1'b0;
        q_rw_pair <= 2'd0;
        q_rw_addr <= 5'd0;
        q_rw_wmask <= 16'hffff;
        q_rw_wdata <= 128'd0;
    end else begin
        q_load_done <= 1'b0;
        q_rw_valid <= 1'b0;
        if (q_load_start && !q_load_busy_reg) begin
            q_load_busy_reg <= 1'b1;
            q_load_count_reg <= 6'd0;
        end

        // O store reads get highest priority — they have no backpressure
        // and o_store_adapter cannot retry a dropped request.
        if (store_q_valid) begin
            q_rw_valid <= 1'b1;
            q_rw_write <= store_q_write;
            q_rw_pair <= store_q_pair;
            q_rw_addr <= store_q_addr;
            q_rw_wmask <= 16'hffff;
            q_rw_wdata <= 128'd0;
        end else if (fin_valid && fin_ready) begin
            q_rw_valid <= 1'b1;
            q_rw_write <= 1'b1;
            q_rw_pair <= fin_pair;
            q_rw_addr <= {fin_page, fin_row, fin_half};
            q_rw_wmask <= 16'hffff;
            q_rw_wdata <= fin_data;
        end else if (q_load_fire) begin
            q_rw_valid <= 1'b1;
            q_rw_write <= 1'b1;
            q_rw_pair <= q_load_count_reg[1:0];
            q_rw_addr <= {q_load_page, q_load_count_reg[5:3], q_load_count_reg[2]};
            q_rw_wmask <= 16'hffff;
            q_rw_wdata <= q_rd_data;
            q_load_count_reg <= q_load_count_reg + 6'd1;
            if (q_load_count_reg == 6'd63) begin
                q_load_busy_reg <= 1'b0;
                q_load_done <= 1'b1;
            end
        end
    end
end

endmodule

`default_nettype wire
