# Verification Plan

Status: baseline run plan for reusable end-to-end scoreboards, DUT output dumps, and PPA gating. Large generated vectors and simulator dumps are regression artifacts; do not commit them by default.

## Current Baseline

- S4/D64 committed fixture: `test_vectors/generated/s4_d64_seed100/`
- Golden source: `model.golden_fixed.attention_fixed`
- Vector format: v1 metadata plus `words16` and stride-padded `beats64` files
- Comparator: `scripts/compare_vector_output.py`
- Numeric regression: S256 Python fixed-point regression
- Performance estimate: tile-aware `scripts/cycle_bandwidth_model.py`
- PPA parser: `scripts/parse_genus_reports.py`

## S4 Top Smoke

1. Load `s4_d64_seed100_Q_beats64.hex`, `K_beats64.hex`, and `V_beats64.hex` into the AXI memory model using the metadata stride:

   ```text
   address = BASE + row * stride_bytes + beat * 8
   ```

2. Run the top smoke with `sequence_length=4`, `dimension=64`, `causal=1`, and the agreed Q/K/V/O base addresses.
3. Dump the O memory region in either format:

   ```text
   <run_dir>/s4_top_O_words16.hex
   <run_dir>/s4_top_O_beats64.hex
   ```

4. Compare against the metadata-located golden:

   ```text
   python -B scripts/compare_vector_output.py --metadata test_vectors/generated/s4_d64_seed100/s4_d64_seed100_metadata.json --dut-hex <run_dir>/s4_top_O_words16.hex --format words16 --require-mae 0 --require-maxae 0 --dump-summary-json <run_dir>/s4_top_compare_words16.json
   python -B scripts/compare_vector_output.py --metadata test_vectors/generated/s4_d64_seed100/s4_d64_seed100_metadata.json --dut-hex <run_dir>/s4_top_O_beats64.hex --format beats64 --require-mae 0 --require-maxae 0 --dump-summary-json <run_dir>/s4_top_compare_beats64.json
   ```

5. A passing smoke requires `status=PASS`, `mae=0`, `maxae=0`, and `max_lsb_error=0` in the summary JSON.

## S256 Scoreboard Extension

1. Generate full-size vectors into an external regression artifact directory:

   ```text
   powershell -ExecutionPolicy Bypass -File scripts/make_s256_vectors.ps1 -OutputDir artifacts/vectors/s256_d64_seed100
   ```

   Equivalent direct command:

   ```text
   python -B scripts/generate_test_vectors.py --seed 100 --sequence-length 256 --dimension 64 --case-name s256_d64_seed100 --output-dir artifacts/vectors/s256_d64_seed100 --stride-bytes 128
   ```

2. Preserve the generated `s256_d64_seed100_metadata.json` with the regression run. Do not commit the generated directory unless a later review explicitly chooses a small fixture subset.
3. Load Q/K/V `*_beats64.hex` into the AXI memory model using metadata fields:

   ```text
   sequence_length = 256
   dimension = 64
   output_rows = 256
   stride_bytes = 128
   beats_per_row = 16
   ```

4. Run top compute for the full causal S256 case. If RTL is still tile-limited, record the tile parameters and partial output rows in the run manifest.
5. Dump O in `beats64` format from the O base region. A `words16` dump is also acceptable if the simulator has a direct word dump path.
6. Compare DUT output:

   ```text
   python -B scripts/compare_vector_output.py --metadata artifacts/vectors/s256_d64_seed100/s256_d64_seed100_metadata.json --dut-hex <run_dir>/s256_top_O_beats64.hex --format beats64 --require-mae 0 --require-maxae 0 --dump-summary-json <run_dir>/s256_top_compare.json
   ```

7. Archive the summary JSON with simulator logs. The key fields are `status`, `elements`, `mae`, `maxae`, `max_lsb_error`, and `first_failure`.

## Failure Localization

- If `first_failure` is non-null, start with `row` and `col`.
- For `beats64` dumps, locate the beat with:

  ```text
  beat_index = row * beats_per_row + floor(col / 4)
  lane = col % 4
  ```

- Confirm whether Q/K/V memory preload is correct at the same row and lane before debugging compute state.
- If all rows fail at a fixed column, inspect lane packing and signed int16 handling.
- If rows fail after a tile boundary, inspect scheduler tile rollover, K/V buffer reuse, and causal mask state.
- If only late rows fail, compare cycle model assumptions against the RTL schedule and outstanding AXI transactions.

## PPA Gate

Only run or report Genus/PPA after the selected scoreboard target passes:

1. S4 top smoke must pass bit-exact compare.
2. S256 run should pass, or any known mismatch must be documented with summary JSON and first-failure coordinates.
3. Run the cycle model for the same shape and tile settings:

   ```text
   python -B scripts/cycle_bandwidth_model.py --sequence-length 256 --dimension 64 --compute-rows 256 --kv-tile-rows 16 --json
   ```

4. Run remote Genus using `docs/synthesis_runbook.md`.
5. Parse returned reports:

   ```text
   python -B scripts/parse_genus_reports.py synth/reports/fa_accel_top --json > synth/reports/fa_accel_top/ppa_summary.json
   python -B scripts/parse_genus_reports.py synth/reports/fa_accel_top --require-clean-check-design
   ```

## Remaining Baseline Gaps

- Full S256 top-compute scoreboard evidence with real DUT O dumps.
- Agreement on where non-committed large vectors and run artifacts live in CI or shared storage.
- Tile-reuse RTL/PPA correlation against `cycle_bandwidth_model.py`.
- Remote Genus reports for the final top parameters and constraints.
