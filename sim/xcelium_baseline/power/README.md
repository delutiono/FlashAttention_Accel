# fa_top power activity and Joules flow

This flow creates a representative zero-delay gate-level activity file for
power estimation. The stimulus uses deterministic nonzero Q/K/V data for an
S256 run and dumps only the `dut` hierarchy during the active compute window.

SHM is useful for SimVision debug, but this flow does not rely on Joules
reading an Xcelium SHM database directly. The default handoff is VCD because it
is portable and easy to package. The generated VCD is gzip-compressed after the
Xcelium run; uncompress it before running Joules if your Joules version does not
accept `.vcd.gz`.

Run from `sim/xcelium_baseline`:

```bash
bash power/run_xcelium_power_activity.sh
JOULES_STD_LIB=/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib \
  bash power/run_joules_power.sh
tar -czf fa_top_power_s256_results.tar.gz power/out
```

`run_joules_power.sh` automatically expands the default
`power/out/activity/fa_top_power_s256.vcd.gz` if the uncompressed VCD is not
present.

If the VCD is still too large for the server flow, convert the uncompressed VCD
to SAIF with the available Cadence utility on that server and point Joules at the
SAIF with:

```bash
JOULES_ACTIVITY_FILE=/path/to/fa_top_power_s256.saif \
JOULES_ACTIVITY_FORMAT=saif \
JOULES_STD_LIB=/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib \
  bash power/run_joules_power.sh
```

Useful environment variables:

- `POWER_ACTIVITY_DIR`: where Xcelium writes the VCD.
- `POWER_VCD`: full VCD path passed into the testbench.
- `JOULES_STD_LIB`: SKY130 hs Liberty file for the mapped netlist.
- `JOULES_SRAM_LIBS`: optional whitespace-separated SRAM Liberty files.
- `JOULES_ACTIVITY_FILE`: uncompressed VCD file used by Joules.
- `JOULES_ACTIVITY_FORMAT`: `vcd` by default; set to `saif` for a converted
  SAIF file.
- `JOULES_OUT_DIR`: Joules report/log directory.
