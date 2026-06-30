`timescale 1ns/1ps

module tb_top_compute_s256_smoke;
  tb_top_compute_s32_smoke #(
    .ROWS         (256),
    .KV_TILE_ROWS (16),
    .MEM_WORDS    (32768),
    .Q_BASE       (64'h0000_0000_0000_1000),
    .K_BASE       (64'h0000_0000_0000_9000),
    .V_BASE       (64'h0000_0000_0001_1000),
    .O_BASE       (64'h0000_0000_0001_9000)
  ) u_tb();
endmodule
