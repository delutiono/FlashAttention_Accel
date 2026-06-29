`timescale 1ns/1ps

module tb_top_compute_s64_smoke;
  tb_top_compute_s32_smoke #(
    .ROWS         (64),
    .KV_TILE_ROWS (16),
    .MEM_WORDS    (8192),
    .Q_BASE       (64'h0000_0000_0000_1000),
    .K_BASE       (64'h0000_0000_0000_3000),
    .V_BASE       (64'h0000_0000_0000_5000),
    .O_BASE       (64'h0000_0000_0000_7000)
  ) u_tb();
endmodule
