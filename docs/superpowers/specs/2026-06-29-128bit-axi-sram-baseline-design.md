# 128-bit AXI + Compliant SRAM Baseline Design

Status: proposed design for the next baseline closure path.

## Purpose

The project goal remains the competition baseline, not a broad redesign:

- `S=256`, `D=64`, single batch, single head.
- Q/K/V/O are signed Q8.8 int16.
- Causal attention is required.
- FlashAttention-style dataflow is required: no full score/probability matrix, online softmax, tiled K/V.
- The final package needs RTL, simulation evidence, Genus PPA reports, and gate-level or post-synthesis simulation evidence when available on the remote EDA server.

The selected path is to move the final PPA-oriented baseline to a 128-bit AXI master and compliant SKY130 SRAM macro implementation, while reusing as much of the existing `genus/` example architecture as practical.

## Decision

Use the `genus/` example as the hardware skeleton for the final PPA branch:

- 128-bit AXI4 master data path.
- AXI4-Lite control register interface.
- Fixed baseline shape: `S=256`, `D=64`.
- `Q group=8` and `K/V tile=8` style scheduling.
- Page/tile manager, load/store adapters, score scheduler, packed compute, and finalize cluster style module partitioning.
- Explicit SRAM macro wrappers and a separate behavioral SRAM model for RTL simulation.

Do not use the `genus/` SRAM macro cells as-is. The final RTL must instantiate only SRAM macros listed in `docs/SKY130_readme.txt`.

Keep the existing project golden model, vector generator, comparator, and numeric regression flow. The algorithm contract does not change when AXI width changes.

## Why 128-bit AXI

For one row of `D=64` Q8.8 data:

- 64-bit AXI needs 16 beats.
- 128-bit AXI needs 8 beats.

The total tensor bytes are unchanged, but 128-bit AXI reduces beat count, address/control overhead, and load/store adapter activity. It also aligns better with wide SRAM banking and row/tile movement. This is likely to improve cycles for the fixed `S=256,D=64` baseline, which matters more than preserving the smaller 64-bit DMA for the final PPA submission.

The cost is wider DMA logic, wider muxing, wider memory models, and more routing pressure. This is acceptable for the final baseline because area limit is generous relative to the expected control/data-path size, and the competition rewards cycle/Fmax/PPA rather than minimal RTL area alone.

## Reuse Strategy

Prefer direct reuse or light adaptation over rewriting.

Direct reuse candidates from `genus/workspace/RTL/`:

- `dma_read_master.v`
- `dma_write_master.v`
- `dma_engine.v`
- `task_ctrl.v`
- `perf_counters.v`
- `page_manager.v`
- `q_load_store_adapter.v`
- `k_load_adapter.v`
- `v_load_adapter.v`
- `o_store_adapter.v`
- `score_scheduler.v`
- `packed_compute_core.v`
- `finalize_cluster.v`
- compute pipeline leaves where their numerical behavior matches the project golden closely enough.

Conditional reuse candidates:

- `axi_lite_regs.v`: reuse is acceptable for baseline smoke if the host driver is AW-first, but either add W-first/AW-W independent tests or document the narrower behavior.
- `score_exp_banked_rom.v`, `score_exp_pipe.v`, `update_state_cluster.v`, `reciprocal_approx.v`, `output_norm_pipe.v`: reuse if their error profile remains within `MAE<=0.03` and `MaxAE<=0.10` against the existing comparator.

Must replace or adapt:

- SRAM macro wrappers and macro instance names.
- Genus scripts and library lists.
- Simulation filelists for the selected SRAM behavioral models.
- Path handling in Tcl scripts, avoiding `eval read_libs $lib_files` style expansion that breaks paths with spaces.

## SRAM Macro Policy

Only SRAM macros listed in `docs/SKY130_readme.txt` may be used in the final design. The example uses non-listed macros, so its SRAM wrapper structure is useful, but its concrete macro cells are not compliant.

Preferred macro selection rule:

- Use 1rw1r macros where simultaneous load/read or compute/read behavior needs it.
- Prefer wider macros or parallel banks that naturally produce a 128-bit beat.
- Keep bank count low enough for area and floorplan sanity, but high enough to avoid serializing the 128-bit data path back down to a narrow internal bus.

Candidate compliant families to evaluate first:

- `sky130_sram_2kbytes_1rw1r_128x128_16`
- `sky130_sram_4kbytes_1rw1r_128x256_8`
- `sky130_sram_8kbytes_1rw1r_128x512_8`
- If wide macros are not available on the remote server, compose 128-bit logical banks from listed narrower macros such as `32x128`, `32x256`, or `64x512`.

Logical SRAM targets:

- Q group buffer: store at least 8 rows x 8 AXI beats = 64 beats of 128 bits.
- K tile buffer: store at least 8 rows x 8 AXI beats = 64 beats of 128 bits.
- V tile buffer: same shape as K tile buffer.
- O staging can share Q/O adapter style if writeback is streamed from finalize.
- ACC/meta storage should follow the example's clustered style, but use compliant macros and the smallest practical depth/width composition.

The first implementation should freeze `STRIDE_BYTES=128` for baseline. Programmable stride can remain readable/writable in the register map, but the baseline report should explicitly state that the closed PPA configuration assumes the default stride.

## Golden and Vector Impact

No algorithm golden changes are required.

Unaffected:

- FP32 attention reference.
- Fixed-point attention reference.
- Causal mask rules.
- exp/reciprocal/online softmax numerical contract.
- `words16` Q/K/V/O files.
- MAE/MaxAE thresholds.

Required engineering additions:

- Add or keep `beats128` packing for Q/K/V input.
- Dump O as `words16` whenever practical, so the existing comparator remains the primary correctness gate.
- If beat dumps are needed, extend the comparator to accept `beats128` explicitly.
- Update AXI memory models and testbenches to 128-bit data, 16-bit strobe, and 8 int16 lanes per beat.

## Remote EDA Flow

The remote server owns Genus, Xcelium, and real library paths. Local scripts should be templates with environment-variable inputs, not hard-coded machine paths.

Required path inputs from the user when implementation starts:

- `STD_CELL_LIB_TT`: readable `sky130_fd_sc_hs__tt_025C_1v80.lib`.
- `STD_CELL_LEF`: standard-cell LEF if the physical synthesis script needs it.
- `TECH_LEF`: `sky130_fd_sc_hs__nom.tlef` or the contest-provided equivalent.
- For each selected SRAM macro: `.lib`, `.lef`, and blackbox `.v`.
- Optional SRAM behavioral `.v` model, if different from the blackbox `.v`.
- Remote command style for Genus and Xcelium, including module setup or environment variables if required by the server.

Script outputs should be collected under stable directories:

- `synth/reports/fa_top_sram128/`
- `synth/outputs/fa_top_sram128/`
- `artifacts/runs/fa_top_sram128_s256_seed100/`

The Genus script should generate:

- `check_design.rpt`
- `area.rpt`
- `gates.rpt`
- `timing.rpt`
- `power.rpt`
- `qor.rpt`
- mapped Verilog netlist
- mapped SDC

The parser should produce `ppa_summary.json` from returned reports.

## Verification Plan

Minimum baseline gates:

1. AXI-Lite register smoke.
2. S256 all-zero RTL run: completes, writes exactly 32 KB of O, and writes zero data.
3. S256 seed100 random scoreboard: `MAE<=0.03`, `MaxAE<=0.10`.
4. Additional targeted corner if time permits: causal row 0, causal row 255, and mixed-sign input.
5. Genus elaboration and `check_design` report.
6. Genus mapped netlist generation.
7. Gate-level or mapped-netlist simulation on the remote server with SRAM models configured consistently.

Use the existing project comparator and metadata flow as the source of truth. Do not require bit-exact equality for the reused `genus/` numeric pipeline unless the imported modules happen to match; the competition threshold allows bounded approximation.

## RTL Style

For imported example modules, preserve the existing Verilog style unless a change is necessary for compliance or integration. For new wrappers and adapters:

- Keep module boundaries narrow and named after their role.
- Add Chinese comments at important scheduling, SRAM mapping, and protocol assumptions.
- Avoid commentary on obvious assignments.
- Keep all paths and macro choices documented in the runbook.

## Non-Goals

The baseline closure does not include:

- Multi-head support.
- `S=512`.
- Padding mask.
- BF16/FP16.
- AXI4-Stream.
- Full AXI-Lite conformance beyond what is needed for the competition host flow, unless a small fix is cheaper than documenting the limitation.
- Rewriting the numerical pipeline if the reused example pipeline passes the official error thresholds.

## Risks and Mitigations

Risk: compliant SRAM macros do not match the example macro shapes.
Mitigation: preserve the example's logical SRAM interfaces, and build wrapper/adaptation layers over listed SKY130 macros.

Risk: 128-bit data path increases timing pressure.
Mitigation: keep the example's pipelined partitioning and run Genus early; avoid adding wide combinational reshapes outside load/store boundaries.

Risk: reused numerical modules differ from the existing bit-exact fixed golden.
Mitigation: gate against competition MAE/MaxAE thresholds rather than project-internal bit-exact equality for this branch.

Risk: remote paths are not known locally.
Mitigation: make scripts environment-variable driven and ask for exact `.lib/.lef/.v` paths before implementation.

Risk: gate-level SRAM simulation model differs from RTL behavioral model.
Mitigation: keep blackbox, behavioral, and timing model filelists separate and document which one each simulation uses.

## Proposed Implementation Order

1. Create a new PPA baseline RTL workspace or branch path for `fa_top_sram128`, leaving the current 64-bit RTL as fallback.
2. Import the minimal set of reusable `genus/` RTL modules.
3. Replace SRAM wrappers with compliant macro wrapper stubs and behavioral models.
4. Connect the existing vector generator/comparator through `beats128` packing and `words16` O dump.
5. Run RTL S256 zero and random scoreboard.
6. Add remote Genus/Xcelium run scripts with environment-variable library paths.
7. Run remote Genus and return reports/outputs.
8. Parse PPA reports and assemble baseline signoff artifacts.

