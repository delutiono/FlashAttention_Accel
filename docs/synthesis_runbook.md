# Synthesis Runbook

This runbook captures the remote Genus flow for collecting real PPA data. The local workspace does not include Genus or complete PDK views, so do not treat local parser output as a completed synthesis run.

## Inputs

- RTL/file list: `rtl/` and `synth/filelist.f`
- Constraints: `synth/constraints.sdc`
- Genus scripts: `synth/run_leaf_genus.tcl`, `synth/run_genus.tcl`
- Standard-cell Liberty timing library: set by `STD_CELL_LIB`
- Optional mainline SRAM macro RTL/Liberty/LEF filelists:
  `SRAM_WRAPPER_FILELIST`, `SRAM_LIB_FILELIST`, and `SRAM_LEF_FILELIST`

Innovus is not required for the current baseline PPA loop. The immediate deliverables are Genus mapped netlist/SDC plus area/timing/power/QoR/check-design reports.

## Remote Commands

Run these commands from the repository root on a machine with Genus and readable standard-cell Liberty views.

For bash/sh:

```sh
export STD_CELL_LIB=/path/to/stdcell.lib
export SRAM_WRAPPER_FILELIST=$PWD/synth/fa_sram_macro_files.list
export SRAM_LIB_FILELIST=$PWD/synth/fa_sram_tt_libs.list
export SRAM_LEF_FILELIST=$PWD/synth/fa_sram_lefs.list
cd synth
TOP=recip genus -batch -files run_leaf_genus.tcl
TOP=fa_accel_top genus -batch -files run_genus.tcl
```

For csh/tcsh, use `setenv` without `=`:

```csh
setenv STD_CELL_LIB /path/to/stdcell.lib
setenv SRAM_WRAPPER_FILELIST $PWD/synth/fa_sram_macro_files.list
setenv SRAM_LIB_FILELIST $PWD/synth/fa_sram_tt_libs.list
setenv SRAM_LEF_FILELIST $PWD/synth/fa_sram_lefs.list
cd synth
setenv TOP recip
genus -batch -files run_leaf_genus.tcl
setenv TOP fa_accel_top
genus -batch -files run_genus.tcl
```

Leaf aliases currently supported by `run_leaf_genus.tcl` are `exp`, `recip`, `softmax`, and `finalize`. Full module names such as `fa_recip_approx` are also accepted.

`synth/run_genus.tcl` defaults the mainline SRAM filelists to the repository copies above when they exist, so the explicit exports are mainly useful when the remote server uses absolute paths or a combined filelist. `SRAM_WRAPPER_FILELIST` should contain the project wrapper RTL plus selected SRAM blackbox Verilog, `SRAM_LIB_FILELIST` should contain the selected SRAM Liberty files, and `SRAM_LEF_FILELIST` should contain SRAM macro LEFs. If your Genus physical flow also requires standard-cell LEFs, create a combined LEF list on the remote server that includes `sky130_fd_sc_hs__nom.tlef`, any required `sky130_fd_sc_hs` cell LEF, and `synth/fa_sram_lefs.list`, then point `SRAM_LEF_FILELIST` at that combined list.

Current boundary: the mainline SRAM wrapper layer and filelists are ready for physical synthesis flows, but `fa_q_buffer` and `fa_kv_buffer` still use register arrays. A PPA run can therefore validate the 128-bit AXI mainline and script plumbing now; a final SRAM-macro PPA claim should wait until the mainline buffers instantiate the `fa_sram_*` wrapper modules or an equivalent compliant SRAM-backed adapter.

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

For the full top-level baseline run, the minimum return package is:

```text
synth/reports/fa_accel_top/
synth/outputs/fa_accel_top/
synth/reports/fa_accel_top/ppa_summary.json
```

If the S256 simulator run was also completed on the remote server, package the verification records with the Genus records:

```text
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log
artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json
synth/reports/fa_accel_top/
synth/outputs/fa_accel_top/
synth/reports/fa_accel_top/ppa_summary.json
```

The generated `artifacts/` tree is not a source change and should not be committed. Return the DUT O dump, such as `artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats128.hex`, only when the comparator fails or output-level debug is needed.

Example package command from the repository root:

```sh
tar -czf fa_accel_s256_genus_return_$(date +%Y%m%d_%H%M%S).tar.gz \
  artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json \
  artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log \
  artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json \
  synth/reports/fa_accel_top \
  synth/outputs/fa_accel_top
```

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
