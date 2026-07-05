# fa_top Xcelium gate-level functional baseline

This directory is the checked-in baseline for simulating the baseline
`fa_top_mapped.v` gate-level netlist with the Xcelium tool
(`xcelium(64) 24.09`).

It is intentionally self-contained for simulation:

- `netlist/fa_top_mapped.v`: synthesized `fa_top` gate netlist.
- `constraints/fa_top_mapped.sdc`: matching SDC for reference only.
- `models/`: primitive, standard-cell, SRAM, and AXI memory models used by the
  gate-level testbenches.
- `tb/`: `fa_top` gate-level functional testbenches.
- `tests/`: AXI memory model sanity tests.
- `filelists/fa_top_gate.f`: source filelist for the gate netlist and models.
- `tcl/run_gate_func.tcl`: final Xcelium run-control script used through
  `xrun -input`.
- `run_xcelium.sh`: user-facing wrapper for gate-level functional simulation.
- `run_mem_model_test.sh`: user-facing wrapper for memory-model sanity tests.

Run from either the repository root or this directory:

```bash
bash sim/xcelium_baseline/run_mem_model_test.sh
bash sim/xcelium_baseline/run_xcelium.sh smoke
bash sim/xcelium_baseline/run_xcelium.sh zero
```

If already inside `sim/xcelium_baseline`, use:

```bash
bash run_mem_model_test.sh
bash run_xcelium.sh smoke
bash run_xcelium.sh zero
```

Available gate simulation cases:

- `smoke`: AXI-Lite register smoke test.
- `zero`: S256 zero-input functional run with diagnostic timeout summary.
- `zero_trace`: `zero` with text trace.
- `zero_xtrace`: `zero` with X tracing and early stop.
- `zero_wrtrace`: alias of the write-path X trace case.
- `scoreboard`: S256 scoreboard test.
- `scoreboard_trace`: scoreboard test with text trace.

The current validated baseline is:

- `run_mem_model_test.sh`: passed on Xcelium 24.09-s006.
- `run_xcelium.sh zero`: passed on Xcelium 24.09-s006 with
  `o_write_beats=2048` and `o_write_bursts=128`.

This is a functional gate-level baseline. It uses `-delay_mode zero` and
`-notimingchecks`; do not use this as SDF timing signoff.
