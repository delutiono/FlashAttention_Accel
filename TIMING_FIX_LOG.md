# 300MHz Timing Fix Progress

## Target
300MHz (3333ps period) on SKY130 HS standard cells.

## Timing Report Analysis (`timing_50paths.rpt`)
50 worst paths all violated (slack range: -193ps ~ -276ps):

| Startpoint | Count | Module | Path Type |
|---|---|---|---|
| `u_finalize/inv_reg_reg[5]` | 21 | output_norm_pipe (lane 0) | 48b×32b multiplier |
| `u_finalize/inv_reg_reg[6]` | 18 | output_norm_pipe (lane 1) | 48b×32b multiplier |
| `u_finalize/inv_reg_reg[1]` | 6 | output_norm_pipe (other bits) | 48b×32b multiplier |
| `u_v_sram_.../clk0` (F) | 1 | V SRAM wrapper | half-cycle SRAM internal |
| `u_acc_sram_.../clk1` (F) | 1 | ACC SRAM wrapper | half-cycle SRAM internal |
| `u_core_u_update/mul_v_data_reg` | 1 | update_state_cluster | V×beta multiply |
| `u_core_issue_scale_mem_reg` | 1 | score_exp_pipe | dot×scale multiply |
| `u_v_adapter_v_rw_data_reg` | 1 | V load adapter → V SRAM | long wire write path |

**结论**: P0 覆盖 45 条（output_norm_pipe 乘法器），P2 覆盖 1 条（update_state_cluster），P3 覆盖 1 条（score_exp_pipe）。剩余 3 条为 SRAM 半周期内部路径和长线物理布线问题，非 RTL 可修。

## Completed Fixes

### P0: `output_norm_pipe.v` — DONE
**File**: `workspace/RTL/output_norm_pipe.v`
**Change**: 3-stage (M→R→S) → 4-stage (M1→M2→R→S)
- M1: registers multiplier inputs (`acc_m1_reg`, `inv_m1_reg`)
- M2: multiply from registered inputs (`product_reg`)
- R: round+shift (unchanged)
- S: saturate (unchanged)
**Impact**: +1 cycle latency, fixes ~45/50 violations

### P2: `update_state_cluster.v` — DONE
**File**: `workspace/RTL/update_state_cluster.v`
**Change**: Insert `mul_mid` pipeline stage between `mul_valid` and `mul_d1`
- Original: mul_valid (multiply) → mul_d1 (shift) → mul2 (add) → sum (writeback)
- New: mul_valid (multiply→mul_mid) → mul_mid (pass-through) → mul_d1 (shift) → mul2 (add) → sum
- New registers: `mul_mid_valid_reg`, `mul_mid_quarter_reg`, `mul_mid_context_reg`, `mul_mid_token_reg`, `mul_mid_last_reg`, `acc_mul_mid_reg[0:15]` (65b), `v_mul_mid_reg[0:15]` (33b)
- Multiply results go to `acc_mul_mid_reg`/`v_mul_mid_reg`, then pass through to `acc_mul_reg`/`v_mul_reg` in next cycle
- `mul_d1_valid_reg` chains from `mul_mid_valid_reg` (was `mul_valid_reg`)
**Impact**: +1 cycle latency

### P3: `score_exp_pipe.v` — DONE
**File**: `workspace/RTL/score_exp_pipe.v`
**Change**: Split 48b×16b multiply into M0 (register inputs) + v0 (multiply from registered inputs)
- Original: v0 (in_valid → product_s0 = in_dot * in_scale)
- New: m0 (in_valid → capture dot_m0, scale_m0, m_old_m0, token_m0) → v0 (m0 → product = dot_m0 * scale_m0)
- New registers: `m0`, `dot_m0` (48b), `scale_m0` (16b), `m_old_m0` (32b), `token_m0`
**Impact**: +1 cycle latency

### P1: SRAM wrapper half-cycle paths — NOT RTL-FIXABLE
Path 1 (V SRAM, slack=-276ps) 和 Path (~50, ACC SRAM) 都在 SRAM wrapper 内部：
- Startpoint: `u_mem/clk0` (SRAM 宏内部时钟，下降沿发射)
- Endpoint: `rw_rdata_reg/D` (wrapper 内部寄存器，上升沿捕获)
- 半周期可用时间 ~1667ps，数据路径 ~2133ps

这是 SRAM 宏自身的时序限制，无法通过 RTL 修改解决。可能的方案：
- 使用更快的 SRAM 宏（不同 PVT corner）
- Physical design 优化 SRAM 到寄存器的布局
- 或换用全周期读出的 SRAM wrapper

### P4: V load adapter → V SRAM write — PHYSICAL ROUTING
`u_v_adapter_v_rw_data_reg` → V SRAM `din0[5]`，数据路径 3248ps，大部分是长线延迟（buf/inv chain with large loads）。这是 V 加载阶段的写路径，非 attention 计算关键路径，可能通过 physical design 改善。

## Total Impact
- **Pipeline latency**: +3 cycles total (negligible vs ~178K total cycles)
- **Area**: ~100-200 additional flip-flops
- **Functional**: No change in behavior, same MAE

## RTL Simulation Verification ✅
- **Date**: 2026-07-06
- **Simulator**: iverilog + vvp
- **Testbench**: `sim/tb_fa_top.sv` (copied from another_workspace)
- **Result**: PASS, STATUS=0x2 (done=1, error=0)
- **Cycles**: 182,243 (vs original ~178K, +4K from +3 pipeline stages, well under 300K limit)
- **Mismatches**: 2547/16384 (all Q8.8 quantization, same as before pipeline changes)
- **MAE**: 0.000613 (identical to original)
- **MaxAE**: 2.0 (identical to original)
- **Sim infrastructure**: `Makefile` + `sim/` directory created in `baseline_300mhz_genus/`

## Next Steps
1. ~~RTL simulation~~ ✅ DONE — functionally verified
2. Re-run Genus synthesis to check timing closure at 300MHz
3. If SRAM half-cycle violations remain after synthesis, evaluate SRAM macro options
