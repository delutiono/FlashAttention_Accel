# Genus Synthesis Flow

## Current Status

The repository contains draft Genus, Yosys, and Innovus flows, but a baseline
top-level PPA result has not been produced. The current project priority is
Genus logic synthesis. Innovus place and route is deferred until the RTL,
DMA, correctness, cycle count, and Genus PPA gates are closed.

The checked-in `sky130_ff.lib` is not a usable timing library: it contains no
Liberty `cell()` definitions. Obtain the full Sky130 HS TT Liberty view from
the remote Cadence server before running synthesis.

The current compute-only top exposes complete Q/K/V/O tensors as very wide
ports. This causes large AST and netlist expansion and is the main reason
full-size Yosys synthesis runs out of memory. More RAM may help diagnose the
design, but the baseline implementation should replace those ports with DMA
and bounded SRAM-style interfaces.

## Required Input

Genus logic synthesis currently requires only the full standard-cell Liberty:

```bash
export STD_CELL_LIB=/pdk/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib
```

Technology LEF, cell LEF, and QRC technology files are only needed when the
project later enters Innovus physical implementation.

## Genus Logic Synthesis

Run from any directory:

```bash
genus -batch -files /path/to/repo/synth/run_genus.tcl
```

Expected outputs:

```text
synth/reports/qor.rpt
synth/reports/area.rpt
synth/reports/timing.rpt
synth/reports/power.rpt
synth/outputs/fa_accel_top_mapped.v
synth/outputs/fa_accel_top_mapped.sdc
```

The script fails early when the Liberty, SDC, or RTL sources are missing.
Passing setup checks does not imply the current wide-port architecture meets
area or timing.

## Yosys Diagnostic Flow

Leaf-module and reduced-parameter scripts remain useful for syntax,
elaboration, and small gate-level simulation:

```bash
yosys synth/synth_modules.ys
yosys synth/synth_small_params.ys
```

`synth/synth_full.ys` is an experimental diagnostic path. It expects the full
TT Liberty file at the repository root as
`sky130_fd_sc_hs__tt_025C_1v80.lib`. Reduced `S`, `D`, or `BK` results are not
baseline PPA evidence.

## Innovus Status

Innovus is not a Baseline prerequisite. The checked-in physical implementation
scripts are drafts and have not been validated against the remote PDK. Do not
use them as completion evidence. Revisit them only after the Genus reports and
all functional Baseline gates pass.

## Remaining Engineering Work

1. Replace full-tensor top ports with implemented AXI DMA and bounded buffers.
2. Remove single-cycle whole-tile copy loops from the scheduler.
3. Reduce the measured 597,761 cycles below the 300k baseline limit.
4. Run independent FP32 MAE/MaxAE scoring.
5. Run Genus with the complete Liberty view and archive the PPA reports.
6. Optionally revisit Innovus after all Baseline gates pass.
