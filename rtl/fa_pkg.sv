package fa_pkg;
  localparam int unsigned FA_S = 256;
  localparam int unsigned FA_D = 64;
  localparam int unsigned FA_ELEM_W = 16;
  localparam int unsigned FA_ADDR_W = 64;
  localparam int unsigned FA_AXI_DATA_W = 64;
  localparam int unsigned FA_AXI_STRB_W = FA_AXI_DATA_W / 8;
  localparam int unsigned FA_STRIDE_DEFAULT = FA_D * (FA_ELEM_W / 8);

  localparam logic [11:0] REG_CTRL         = 12'h000;
  localparam logic [11:0] REG_STATUS       = 12'h004;
  localparam logic [11:0] REG_CFG          = 12'h008;
  localparam logic [11:0] REG_Q_BASE_L     = 12'h014;
  localparam logic [11:0] REG_Q_BASE_H     = 12'h018;
  localparam logic [11:0] REG_K_BASE_L     = 12'h01c;
  localparam logic [11:0] REG_K_BASE_H     = 12'h020;
  localparam logic [11:0] REG_V_BASE_L     = 12'h024;
  localparam logic [11:0] REG_V_BASE_H     = 12'h028;
  localparam logic [11:0] REG_O_BASE_L     = 12'h02c;
  localparam logic [11:0] REG_O_BASE_H     = 12'h030;
  localparam logic [11:0] REG_STRIDE_BYTES = 12'h034;
  localparam logic [11:0] REG_NEG_LARGE    = 12'h038;
  localparam logic [11:0] REG_SCALE        = 12'h03c;
  localparam logic [11:0] REG_CYCLES       = 12'h040;

  typedef enum logic [3:0] {
    FA_ST_IDLE,
    FA_ST_CHECK_CFG,
    FA_ST_LOAD_Q,
    FA_ST_INIT_ROW,
    FA_ST_LOAD_KV,
    FA_ST_COMPUTE_TILE,
    FA_ST_FINALIZE,
    FA_ST_WRITE_O,
    FA_ST_DONE,
    FA_ST_ERROR
  } fa_state_e;
endpackage
