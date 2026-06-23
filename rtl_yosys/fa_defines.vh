// fa_defines.vh — Yosys-compatible (no package/import needed)
`ifndef FA_DEFINES_VH
`define FA_DEFINES_VH

  `define FA_S 256
  `define FA_D 64
  `define FA_ELEM_W 16
  `define FA_ADDR_W 64
  `define FA_AXI_DATA_W 64
  `define FA_AXI_STRB_W 8
  `define FA_STRIDE_DEFAULT (`FA_D * (`FA_ELEM_W / 8))

  `define REG_CTRL         12'h000
  `define REG_STATUS       12'h004
  `define REG_CFG          12'h008
  `define REG_Q_BASE_L     12'h014
  `define REG_Q_BASE_H     12'h018
  `define REG_K_BASE_L     12'h01c
  `define REG_K_BASE_H     12'h020
  `define REG_V_BASE_L     12'h024
  `define REG_V_BASE_H     12'h028
  `define REG_O_BASE_L     12'h02c
  `define REG_O_BASE_H     12'h030
  `define REG_STRIDE_BYTES 12'h034
  `define REG_NEG_LARGE    12'h038
  `define REG_SCALE        12'h03c
  `define REG_CYCLES       12'h040

`endif
