# fa_top Xcelium gate-level functional baseline

This directory is the checked-in baseline for simulating the baseline
`fa_top_mapped.v` gate-level netlist with the Xcelium tool
(`xcelium(64) 24.09`).

It is intentionally self-contained for simulation:

- `netlist/fa_top_mapped.v`: synthesized `fa_top` gate netlist.
- `constraints/fa_top_mapped.sdc`: matching SDC for reference only.
- `timing/fa_top_mapped.sdf`: matching SDF for timing simulation.
- `models/`: primitive, standard-cell, SRAM, and AXI memory models used by the
  gate-level testbenches. `sky130_fd_sc_hs_sdf_minimal.v` is the SDF-capable
  standard-cell model used by the `sdf_*` cases.
- `tb/`: `fa_top` gate-level functional testbenches.
- `tests/`: AXI memory model sanity tests.
- `filelists/fa_top_gate.f`: source filelist for zero-delay gate simulation.
- `filelists/fa_top_gate_sdf.f`: source filelist for SDF gate simulation.
- `tcl/run_gate_func.tcl`: final Xcelium run-control script used through
  `xrun -input`.
- `run_xcelium.sh`: user-facing wrapper for gate-level functional simulation.
- `run_mem_model_test.sh`: user-facing wrapper for memory-model sanity tests.

Run from either the repository root or this directory:

```bash
bash sim/xcelium_baseline/run_mem_model_test.sh
bash sim/xcelium_baseline/run_xcelium.sh smoke
bash sim/xcelium_baseline/run_xcelium.sh zero
bash sim/xcelium_baseline/run_xcelium.sh sdf_smoke
bash sim/xcelium_baseline/run_xcelium.sh sdf_s256
```

If already inside `sim/xcelium_baseline`, use:

```bash
bash run_mem_model_test.sh
bash run_xcelium.sh smoke
bash run_xcelium.sh zero
bash run_xcelium.sh sdf_smoke
bash run_xcelium.sh sdf_s256
```

Available gate simulation cases:

- `smoke`: AXI-Lite register smoke test.
- `zero`: S256 zero-input functional run with diagnostic timeout summary.
- `zero_trace`: `zero` with text trace.
- `zero_xtrace`: `zero` with X tracing and early stop.
- `zero_wrtrace`: alias of the write-path X trace case.
- `sdf_smoke`: AXI-Lite smoke test with `timing/fa_top_mapped.sdf` annotated.
- `sdf_s256`: S256 zero-input run with `timing/fa_top_mapped.sdf` annotated.
- `sdf_s256_trace`: `sdf_s256` with text trace.
- `scoreboard`: S256 scoreboard test.
- `scoreboard_trace`: scoreboard test with text trace.

The current validated baseline is:

- `run_mem_model_test.sh`: passed on Xcelium 24.09-s006.
- `run_xcelium.sh zero`: passed on Xcelium 24.09-s006 with
  `o_write_beats=2048` and `o_write_bursts=128`.
- `run_xcelium.sh sdf_smoke`: passed on Xcelium 24.09-s006.
- `run_xcelium.sh sdf_s256`: passed on Xcelium 24.09-s006 with
  `o_write_beats=2048`, `o_write_bursts=128`, and no `SDFNEP` annotation
  warnings in the checked SDF logs.

The `smoke`, `zero`, trace, and scoreboard cases use `-delay_mode zero`,
`-notimingchecks`, and `-define FUNCTIONAL`.

The `sdf_*` cases compile the SDF-capable standard-cell model, annotate
`timing/fa_top_mapped.sdf` onto the testbench `dut` instance through
`$sdf_annotate`, and run with `-notimingchecks`. This mode verifies SDF
back-annotation and delayed gate-level functionality; it is not a timing-closure
pass/fail signoff. Xcelium writes the SDF annotation report to
`sdf_annotate.log` in this directory.

The SDF S256 case is named `sdf_s256` rather than `sdf_zero` to avoid confusing
the zero-input stimulus with zero-delay simulation. The script still accepts
`sdf_zero` and `sdf_zero_trace` as backward-compatible aliases.

The standard-cell `specify` timing information used for SDF simulation is based
on the open-source SkyWater SKY130 PDK standard-cell Verilog models, including
the `sky130_fd_sc_hs` library. See
[google/skywater-pdk](https://github.com/google/skywater-pdk).

The SDF/netlist pair came from `genus_bs_xcem/results/outputs/fa_top`. Its
source RTL snapshot is not byte-identical to this repository's current
`workspace/RTL` tree after normalizing line endings, so treat this directory as
the self-contained gate-simulation baseline for that mapped netlist.
