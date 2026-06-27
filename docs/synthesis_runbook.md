# Synthesis Runbook

This runbook captures the remote Genus flow for collecting real PPA data. The local workspace does not include Genus or complete PDK views, so do not treat local parser output as a completed synthesis run.

## Inputs

- RTL/file list: `rtl/` and `synth/filelist.f`
- Constraints: `synth/constraints.sdc`
- Genus scripts: `synth/run_leaf_genus.tcl`, `synth/run_genus.tcl`
- Liberty timing library: set by `STD_CELL_LIB`

Innovus is not required for the current baseline PPA loop. The immediate deliverables are Genus mapped netlist/SDC plus area/timing/power/QoR/check-design reports.

## Remote Commands

Run these commands from the repository root on a machine with Genus and readable standard-cell Liberty views.

For bash/sh:

```sh
export STD_CELL_LIB=/path/to/stdcell.lib
cd synth
TOP=recip genus -batch -files run_leaf_genus.tcl
TOP=fa_accel_top genus -batch -files run_genus.tcl
```

For csh/tcsh, use `setenv` without `=`:

```csh
setenv STD_CELL_LIB /path/to/stdcell.lib
cd synth
setenv TOP recip
genus -batch -files run_leaf_genus.tcl
setenv TOP fa_accel_top
genus -batch -files run_genus.tcl
```

Leaf aliases currently supported by `run_leaf_genus.tcl` are `exp`, `recip`, `softmax`, and `finalize`. Full module names such as `fa_recip_approx` are also accepted.

## Expected Artifacts

For each `TOP`, collect:

- `synth/reports/<top>/check_design.rpt`
- `synth/reports/<top>/area.rpt`
- `synth/reports/<top>/timing.rpt`
- `synth/reports/<top>/power.rpt`
- `synth/reports/<top>/qor.rpt`
- `synth/outputs/<top>/<top>_mapped.v`
- `synth/outputs/<top>/<top>_mapped.sdc`

Package the matching `reports/<top>` and `outputs/<top>` directories together when returning remote results. If Genus fails before writing all reports, still return the partial directory so the parser can mark missing files explicitly.

## PPA Summary

After copying remote artifacts back to the repo, summarize each report directory:

```sh
python -B scripts/parse_genus_reports.py synth/reports/fa_recip_approx
python -B scripts/parse_genus_reports.py synth/reports/fa_accel_top
python -B scripts/parse_genus_reports.py synth/reports/fa_accel_top --json > synth/reports/fa_accel_top/ppa_summary.json
python -B scripts/parse_genus_reports.py synth/reports/fa_accel_top --require-clean-check-design
```

The parser is intentionally tolerant: missing report files are recorded in JSON under `summary.missing_reports` instead of causing a crash. Use `--require-clean-check-design` in CI or release checks when a dirty or missing `check_design.rpt` should fail the command.

## PPA Closure Notes

- Area is taken from `area.rpt` first, then `qor.rpt` if needed.
- WNS/TNS are taken from `qor.rpt` first, then `timing.rpt` if needed.
- Power currently records report units as emitted by Genus; confirm the library/process units in the remote environment before comparing against external targets.
- A complete PPA claim requires real remote Genus output, not local fake reports or parser unit tests.
