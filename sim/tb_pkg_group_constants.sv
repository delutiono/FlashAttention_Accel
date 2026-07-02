`timescale 1ns/1ps

module tb_pkg_group_constants;
  import fa_pkg::*;

  initial begin
    if (FA_Q_GROUP_ROWS !== 8) $fatal(1, "FA_Q_GROUP_ROWS mismatch");
    if (FA_KV_TILE_ROWS !== 8) $fatal(1, "FA_KV_TILE_ROWS mismatch");
    if (FA_GROUPS !== 32) $fatal(1, "FA_GROUPS mismatch");
    if (FA_AXI_LANES !== 8) $fatal(1, "FA_AXI_LANES mismatch");
    if (FA_ROW_BEATS !== 8) $fatal(1, "FA_ROW_BEATS mismatch");
    if (FA_GROUP_BEATS !== 64) $fatal(1, "FA_GROUP_BEATS mismatch");
    $display("tb_pkg_group_constants PASS");
    $finish;
  end
endmodule
