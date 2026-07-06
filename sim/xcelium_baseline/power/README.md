# fa_top zero-delay Xreplay power flow

This directory is the power calculation work environment for the
`xcelium_baseline` branch. The primary flow is zero-delay Joules Xreplay:

```text
RTL power stimulus waveform
+ Genus RTL-to-gate mapping file
+ netlist/fa_top_mapped.v
+ constraints/fa_top_mapped.sdc
+ Liberty files
-> Joules xreplay -delay_mode zero
-> power reports
```

This power flow does not use SDF. SDF gate simulation remains in the baseline
directory for timing/back-annotation checks, but power uses zero-delay replay.

## Required Inputs

- `netlist/fa_top_mapped.v`: mapped netlist.
- `constraints/fa_top_mapped.sdc`: clock constraints for Joules.
- `power/mapping/fa_top_genus_mapping.rpt`: Genus RTL-to-gate mapping file from
  the same Genus run as `fa_top_mapped.v`.
- `power/rtl_wave/fa_top_power_s256_rtl.shm`: RTL waveform from the same RTL
  snapshot used by Genus. Use `RTL_DIR` if the RTL is not in
  `../../workspace/RTL`.
- `JOULES_STD_LIB`: SKY130 hs Liberty file path.
- `JOULES_SRAM_LIBS`: optional whitespace-separated SRAM Liberty files.

## Run

From `sim/xcelium_baseline`:

```bash
bash power/scripts/run_rtl_power_activity.sh
JOULES_STD_LIB=/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib \
  bash power/scripts/run_joules_xreplay_zero.sh
tar -czf fa_top_power_s256_results.tar.gz power/out
```

The RTL run prints `POWER_WINDOW_START` and `POWER_WINDOW_END` markers in
`power/logs/rtl_power_s256/xrun_rtl_power.log`. If you want Xreplay to focus on
that window, pass those times to Joules:

```bash
JOULES_XREPLAY_START=12345ns \
JOULES_XREPLAY_END=67890ns \
JOULES_STD_LIB=/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib \
  bash power/scripts/run_joules_xreplay_zero.sh
```

## Directory Layout

- `scripts/`: user-facing wrappers for RTL activity and Joules Xreplay.
- `tcl/`: Xcelium/Joules TCL scripts.
- `mapping/`: same-source Genus RTL-to-gate mapping file.
- `rtl_wave/`: generated RTL stimulus waveform.
- `logs/`: tool logs.
- `out/`: Xreplay output stimulus and Joules reports.

## Fallback VCD Flow

The older gate-level VCD based flow is kept as a fallback:

```bash
bash power/run_xcelium_power_activity.sh
JOULES_STD_LIB=/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib \
  bash power/run_joules_power.sh
```

Prefer Xreplay when the gate-level VCD is too slow or too large.

## Alternative RTL VCD

```bash
RTL_WAVE_FORMAT=vcd bash power/scripts/run_rtl_power_activity.sh
JOULES_RTL_STIM=power/rtl_wave/fa_top_power_s256_rtl.vcd \
JOULES_RTL_STIM_FORMAT=vcd \
  bash power/scripts/run_joules_xreplay_zero.sh
```

Use RTL VCD only if your Joules/Xreplay installation cannot consume Xcelium SHM.

## Important

The mapping file, RTL waveform, and mapped netlist must be same-source. Do not
mix old mapping with a regenerated netlist, or a waveform from a different RTL
snapshot.
