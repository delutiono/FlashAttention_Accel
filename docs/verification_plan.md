# Verification Plan

Status: baseline run plan for reusable end-to-end scoreboards, DUT output dumps, and PPA gating. Large generated vectors and simulator dumps are regression artifacts; do not commit them by default.

## Current Baseline

- S4/D64 committed fixture: `test_vectors/generated/s4_d64_seed100/`
- S5/D64 committed fixture: `test_vectors/generated/s5_d64_seed101/`
- S16/D64 committed fixture: `test_vectors/generated/s16_d64_seed102/`
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

## S5 Tile Boundary Fixture

The committed `test_vectors/generated/s5_d64_seed101/` fixture is a small scheduler boundary case for `KV_TILE_ROWS=2`. Its five rows force a `2 + 2 + 1` K/V tile sequence, so it is useful for checking last-tile row count, causal mask rollover, and output writeback after a non-full final tile.

The matching cycle-model command is:

```text
python -B scripts/cycle_bandwidth_model.py --sequence-length 5 --dimension 64 --max-rows 5 --kv-tile-rows 2 --json
```

The expected scheduler-shape fields are `compute_rows=5`, `kv_tile_rows=2`, `kv_tile_count=3`, and `last_kv_tile_rows=1`. A corresponding RTL top smoke should use the same values, consume K/V tiles as `2 + 2 + 1`, and only treat the final tile's first row as valid.

Use the metadata-located golden for self-checks and future DUT dumps:

```text
python -B scripts/compare_vector_output.py --metadata test_vectors/generated/s5_d64_seed101/s5_d64_seed101_metadata.json --dut-hex test_vectors/generated/s5_d64_seed101/s5_d64_seed101_O_golden.hex --format words16 --require-mae 0 --require-maxae 0
python -B scripts/compare_vector_output.py --metadata test_vectors/generated/s5_d64_seed101/s5_d64_seed101_metadata.json --dut-hex test_vectors/generated/s5_d64_seed101/s5_d64_seed101_O_golden_beats64.hex --format beats64 --require-mae 0 --require-maxae 0
```

## S16 Multi-Tile Fixture

The committed `test_vectors/generated/s16_d64_seed102/` fixture is the medium bring-up step between boundary smoke and the full baseline. It keeps the baseline dimension `D=64` and stride `128`, but raises the sequence to 16 rows so a top-level scheduler can exercise multiple complete K/V tiles without committing the full S256 artifact.

Suggested RTL use:

- `KV_TILE_ROWS=4` gives four complete tiles: `4 + 4 + 4 + 4`.
- `KV_TILE_ROWS=8` gives two complete tiles: `8 + 8`.
- `COMPUTE_ROWS=16` checks every causal output row in the committed fixture.

Generate or refresh the fixture with:

```text
python -B scripts/generate_test_vectors.py --seed 102 --sequence-length 16 --dimension 64 --case-name s16_d64_seed102 --output-dir test_vectors/generated/s16_d64_seed102 --stride-bytes 128
```

Use the metadata-located golden for self-checks and future DUT dumps:

```text
python -B scripts/compare_vector_output.py --metadata test_vectors/generated/s16_d64_seed102/s16_d64_seed102_metadata.json --dut-hex test_vectors/generated/s16_d64_seed102/s16_d64_seed102_O_golden.hex --format words16 --require-mae 0 --require-maxae 0
python -B scripts/compare_vector_output.py --metadata test_vectors/generated/s16_d64_seed102/s16_d64_seed102_metadata.json --dut-hex test_vectors/generated/s16_d64_seed102/s16_d64_seed102_O_golden_beats64.hex --format beats64 --require-mae 0 --require-maxae 0
```

The expected cycle-model shape for the preferred S16 gate is:

```text
python -B scripts/cycle_bandwidth_model.py --sequence-length 16 --dimension 64 --compute-rows 16 --kv-tile-rows 4 --json
```

The important fields are `compute_rows=16`, `kv_tile_count=4`, `last_kv_tile_rows=4`, and `tile_reuse_read_bytes=6144`.
These cycle-model numbers describe the target tile-reuse/PPA direction. The current functional top smoke allows K/V row reads anywhere from one full K/V pass through the causal per-query reload upper bound, so future RTL can reduce traffic without invalidating the correctness scoreboard.

Run the existing S16 top scoreboard before S256:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_top_compute_s16_scoreboard.ps1
```

The default artifact locations are:

```text
build/top_compute_s16/o_beats64.hex
build/top_compute_s16/summary.json
```

The comparator gate should require bit-exact output:

```text
python -B scripts/compare_vector_output.py --metadata test_vectors/generated/s16_d64_seed102/s16_d64_seed102_metadata.json --dut-hex build/top_compute_s16/o_beats64.hex --format beats64 --require-mae 0 --require-maxae 0 --dump-summary-json build/top_compute_s16/summary.json
```

This fixture should pass before spending simulator time on S256 because it catches multi-tile rollover, repeated Q row reuse, K/V tile reload cadence, and O row writeback across more than one tile group.

## S256 Scoreboard Extension

The full baseline gate should expand from S16 to S256 in this order:

1. Pass S16 bit-exact scoreboard first, including the `build/top_compute_s16/summary.json` record.
2. Generate full-size vectors into an external regression artifact directory. The default location is under `artifacts/`, which is intentionally not part of the committed regression fixture set:

   ```text
   powershell -ExecutionPolicy Bypass -File scripts/make_s256_vectors.ps1 -OutputDir artifacts/vectors/s256_d64_seed100
   ```

   Equivalent direct command:

   ```text
   python -B scripts/generate_test_vectors.py --seed 100 --sequence-length 256 --dimension 64 --case-name s256_d64_seed100 --output-dir artifacts/vectors/s256_d64_seed100 --stride-bytes 128
   ```

3. Preserve the generated `s256_d64_seed100_metadata.json` with the regression run. Do not commit the generated S256 vector directory, DUT dumps, simulator logs, or generated run summaries unless a later review explicitly chooses a small fixture subset.
4. Emit the matching JSON run manifest and cycle-model target path without creating large artifacts:

   ```text
   python -B scripts/print_s256_regression_manifest.py
   python -B scripts/print_s256_regression_manifest.py --json
   ```

   The JSON manifest records the recommended paths:

   ```text
   artifacts/vectors/s256_d64_seed100/s256_d64_seed100_metadata.json
   artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats64.hex
   artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json
   artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json
   artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log
   ```

5. Run the cycle model and keep the JSON beside the simulator logs:

   ```text
   python -B scripts/cycle_bandwidth_model.py --sequence-length 256 --dimension 64 --compute-rows 256 --kv-tile-rows 16 --json > artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json
   ```

6. Load Q/K/V `*_beats64.hex` into the AXI memory model using metadata fields:

   ```text
   sequence_length = 256
   dimension = 64
   output_rows = 256
   stride_bytes = 128
   beats_per_row = 16
   ```

7. Run top compute for the full causal S256 case locally or on the remote simulator. If local long simulation exceeds the acceptable turnaround time, move this step to the remote server and use the manifest paths as the artifact contract. If RTL is still tile-limited, record the tile parameters and partial output rows in the run manifest.
8. Dump O in `beats64` format from the O base region. A `words16` dump is also acceptable if the simulator has a direct word dump path.
9. Compare DUT output:

   ```text
   python -B scripts/compare_vector_output.py --metadata artifacts/vectors/s256_d64_seed100/s256_d64_seed100_metadata.json --dut-hex <run_dir>/s256_top_O_beats64.hex --format beats64 --require-mae 0 --require-maxae 0 --dump-summary-json <run_dir>/s256_top_compare.json
   ```

10. Archive the summary JSON with simulator logs. The key fields are `status`, `elements`, `mae`, `maxae`, `max_lsb_error`, and `first_failure`.
11. When using the remote server, return at least the compare summary JSON, simulator log, cycle-model JSON, and any Genus report directory produced by that run. Large vector dumps may stay remote if the summary passes; return the DUT dump only when debugging a mismatch.
12. Only after the S256 scoreboard gate passes, run remote Genus/PPA and parse the returned reports.

## Remote Return Package

Generated S256 vectors, DUT dumps, simulator logs, cycle-model JSON, and Genus output are run artifacts. Keep them under `artifacts/`, `build/`, `synth/reports/`, or `synth/outputs/` and do not commit them by default.

After a remote S256 verification plus Genus run, return this minimum package:

```text
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json
artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log
artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json
synth/reports/fa_accel_top/
synth/outputs/fa_accel_top/
synth/reports/fa_accel_top/ppa_summary.json
```

Return `artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats64.hex` only when the comparator reports a mismatch or when line-by-line output debug is needed.

The manifest prints the same contract:

```text
python -B scripts/print_s256_regression_manifest.py --json
```

One portable packaging command from the repository root is:

```sh
tar -czf s256_genus_return_$(date +%Y%m%d_%H%M%S).tar.gz \
  artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json \
  artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log \
  artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json \
  synth/reports/fa_accel_top \
  synth/outputs/fa_accel_top
```

If the S256 compare fails, include the DUT dump in the package:

```sh
tar -czf s256_debug_return_$(date +%Y%m%d_%H%M%S).tar.gz \
  artifacts/runs/s256_d64_seed100 \
  synth/reports/fa_accel_top \
  synth/outputs/fa_accel_top
```

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
- RTL top-compute scoreboard coverage for the committed S16 multi-tile fixture.
- Agreement on where non-committed large vectors and run artifacts live in CI or shared storage.
- Tile-reuse RTL/PPA correlation against `cycle_bandwidth_model.py`.
- Remote Genus reports for the final top parameters and constraints.
