# Baseline Status and Signoff Checklist

Status: working baseline closure checklist for the FlashAttention-style attention IP.

The project target remains a synthesizable, verifiable, and PPA-measurable hardware IP for the product baseline:

- `S=256`
- `D=64`
- `batch=1`
- `head=1`
- causal attention
- Q8.8 input and output data
- FlashAttention-style tiled online softmax dataflow

## Completed Layered Verification Gates

These gates are local bring-up evidence. They reduce risk before the full S256 and Genus closure runs, but they do not replace the final baseline evidence.

| Gate | Purpose | Runner or Evidence | Status |
|---|---|---|---|
| S4 top compute | Small committed end-to-end smoke with bit-exact O compare | `scripts/run_top_compute_s4_scoreboard.ps1` | Available |
| S5 partial tile | Last K/V tile boundary, `2 + 2 + 1`, causal rollover | `scripts/run_top_compute_s5_scoreboard.ps1` | Available |
| S5 stall | AXI stall/backpressure coverage for the S5 boundary path | `scripts/run_top_compute_s5_stall_scoreboard.ps1` | Available |
| S16 multi-tile | Medium committed multi-tile smoke before larger generated cases | `scripts/run_top_compute_s16_scoreboard.ps1` | Available |
| S32 generated | Larger generated local step, default memory still manageable | `scripts/run_top_compute_s32_scoreboard.ps1` | Available |
| S64 generated | Larger generated local step with separated Q/K/V/O bases | `scripts/run_top_compute_s64_scoreboard.ps1` | Available |
| Numeric S256 | Algorithm fixed-point regression over S256 seeds | `scripts/run_numeric_regression.py` | Available |
| Cycle model | Tile-aware bandwidth and cycle estimate | `scripts/cycle_bandwidth_model.py` | Available |
| S256 manifest | Remote artifact contract and commands | `scripts/print_s256_regression_manifest.py` | Available |
| Genus flow | Synthesis scripts, SDC, report parser, remote runbook | `synth/run_genus.tcl`, `synth/constraints.sdc`, `scripts/parse_genus_reports.py`, `docs/synthesis_runbook.md` | Available |
| Mainline SRAM macro buffers | Q/K/V buffers instantiate compliant SKY130 SRAM wrappers | `rtl/fa_q_buffer.sv`, `rtl/fa_kv_buffer.sv`, `rtl/fa_sram_macros.v` | Available |

## Final Baseline Evidence Still Required

Baseline signoff requires real returned artifacts from the full S256 verification and remote Genus run. The minimum package is:

```text
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log
artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json
synth/reports/fa_accel_top/
synth/outputs/fa_accel_top/
synth/reports/fa_accel_top/ppa_summary.json
```

The DUT O dump is intentionally not part of the minimum package:

```text
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats128.hex
```

Return that dump only when the comparator reports a mismatch or when line-by-line debug is needed.

## Artifact Presence Check

Use this lightweight checker after copying remote results back into the repository root:

```text
python -B scripts/check_baseline_artifacts.py
python -B scripts/check_baseline_artifacts.py --json
python -B scripts/check_baseline_artifacts.py --require-complete
```

The checker only reports whether required files and directories are present. It does not read the large DUT dump, and it does not prove functional or PPA signoff by itself.

## Baseline Signoff Criteria

Treat the baseline as signable only when all of these are true:

1. S4, S5, S5 stall, S16, S32, and S64 scoreboard runners pass with bit-exact output.
2. Full S256 compare summary exists and reports `status=PASS`, `mae=0`, `maxae=0`, and `max_lsb_error=0`.
3. S256 simulator log exists and shows the top run completed without simulator errors or unexplained protocol failures.
4. S256 cycle-model JSON exists for the same `sequence_length`, `dimension`, `compute_rows`, and `kv_tile_rows` used by the top simulation.
5. Genus top reports and outputs exist for `fa_accel_top`.
6. `ppa_summary.json` exists and was generated from the returned Genus reports.
7. `check_design.rpt` is clean, or every warning/error is explicitly explained and accepted in the final report.
8. The final report records area, timing, power, QoR, the target clock/SDC used, and any remaining limitations.

If any of these items are missing, the project can still be progressing correctly, but it is not ready for final baseline signoff.

## Current Local Mainline Evidence

The local grouped page/tile-reuse RTL now has full S256 top-compute evidence:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_top_compute_s256_scoreboard.ps1 -RunSimulation -WorkLib work_top_compute_s256_group_tile
```

Latest local result:

```text
PASS elements=16384 mae=0 maxae=0 max_lsb_error=0 first_failure=none
cycles=249697
q_group_reads=32
k_tile_reads=528
v_tile_reads=528
o_group_writes=32
```

The read/write counters above are grouped 64-beat burst counts. In row terms they correspond to `Q=256`, `K=4224`, `V=4224`, and `O=256`, matching the planned 8-row Q group and 8-row K/V tile reuse model.

Evidence paths:

```text
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats128.hex
```

The remaining main gap is the real remote Genus report package for the macro-backed RTL.
