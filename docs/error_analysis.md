# Reciprocal NR Error Analysis

Date: 2026-06-26

## Scope

This report evaluates the division-free oracle now used by the default `model/golden_fixed.py` finalization path. Exact reciprocal remains an explicit comparison mode. The full run uses:

- `S=256`, `D=64`, causal attention.
- Seeds `100,101,102,103,104`.
- `1280` final row denominators and `81920` final Q8.8 output elements.
- Default reciprocal mode `nr`, 32 LUT entries, one NR iteration, four-cycle RTL-valid latency.
- Final error measured against the independent ideal-softmax floating reference.

Reproduce:

```text
python -B scripts/run_numeric_regression.py --seeds 100,101,102,103,104 --sequence-length 256 --dimension 64 --require-mae 0.03 --require-maxae 0.10 --require-candidate-exact-max-lsb 1
```

## Default-Path Closure

The default fixed golden path passes both required gates:

| Gate | Seeds | Candidate MAE | Candidate MaxAE | Exact-final MAE | Candidate vs exact |
|---|---|---:|---:|---:|---:|
| `S=64,D=64` | 100-104 | 0.00394442 | 0.03223060 | 0.00394422 | 51/20480 changed, max 1 LSB |
| `S=256,D=64` | 100-104 | 0.00236523 | 0.03811298 | 0.00236447 | 108/81920 changed, max 1 LSB |

Both are below `MAE<=0.03` and `MaxAE<=0.10`. The exact CLI comparison is:

```text
python -B scripts/run_numeric_regression.py --recip-mode exact ...
```

It reports LUT, iterations, and latency as zero because exact division is a model-only reference, not the RTL pipeline.

## Error Attribution

`run_numeric_regression.py` reports three complementary views from the same final `m/l/acc` state:

- `pwl_fixed_vs_ideal`: exact reciprocal finalization versus ideal softmax. This includes Q8.8 inputs, score scaling/wrapping, exp PWL, online rescale truncation/wrapping, and final Q8.8 rounding/saturation.
- `reciprocal_vs_exact`: default NR finalization versus exact reciprocal finalization. At `S=256`, mean delta is `0.001318` Q8.8 LSB, maximum delta is `1` LSB, and `108` outputs change.
- `candidate_vs_ideal`: the complete default path versus ideal softmax. This is the acceptance MAE/MaxAE.

The reciprocal contribution is therefore bounded to one final-output LSB in the required seeds; the observed MaxAE is controlled by the pre-reciprocal fixed-point path rather than the 32x1 reciprocal.

## Denominator Distribution

Observed `U9.23` denominator range:

- Minimum: `1.00000000`, hex `00800000`.
- Maximum: `136.15439129`, hex `4413C318`.
- P50: `58.16354167`.
- P90: `103.07012701`.
- P99: `123.45880890`.

Power-of-two histogram:

| Real interval | Count |
|---|---:|
| `[1,2)` | 11 |
| `[2,4)` | 18 |
| `[4,8)` | 37 |
| `[8,16)` | 78 |
| `[16,32)` | 170 |
| `[32,64)` | 388 |
| `[64,128)` | 569 |
| `[128,256)` | 9 |

The sampled baseline stays in the expected `l>=1` domain. Most rows lie in `[32,128)`, while the normalization contract still covers every nonzero 32-bit `U9.23` value.

## Candidate Sweep

The exact reciprocal baseline produces `MAE=0.00236447` and `MaxAE=0.03811298`. All candidates pass the required `MAE<=0.03` and `MaxAE<=0.10`.

| LUT | NR | Latency | Final MAE | Final MaxAE | Max recip rel. error | Changed vs exact final | Max final delta |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 8 | 1 | 4 | 0.00238813 | 0.03811298 | 0.003460208 | 1794 | 2 LSB |
| 8 | 2 | 6 | 0.00236447 | 0.03811298 | 0.000011973 | 3 | 1 LSB |
| 16 | 1 | 4 | 0.00236718 | 0.03811298 | 0.000918274 | 400 | 1 LSB |
| 16 | 2 | 6 | 0.00236447 | 0.03811298 | 0.000000843 | 0 | 0 LSB |
| 32 | 1 | 4 | 0.00236523 | 0.03811298 | 0.000236687 | 108 | 1 LSB |
| 32 | 2 | 6 | 0.00236447 | 0.03811298 | 0.000000092 | 0 | 0 LSB |
| 64 | 1 | 4 | 0.00236452 | 0.03811298 | 0.000060093 | 17 | 1 LSB |
| 64 | 2 | 6 | 0.00236447 | 0.03811298 | 0.000000063 | 0 | 0 LSB |

`Changed vs exact final` counts Q8.8 elements whose result differs from the unchanged exact-reciprocal main path. It is not an error against the floating reference.

## Recommendation

The default golden and frozen RTL target use **32 LUT entries and 1 NR iteration**:

- Same 4-cycle latency as other one-iteration choices.
- `1024` ROM bits.
- Final `MAE=0.00236523`, over 12 times below the `0.03` limit.
- Final `MaxAE=0.03811298`, over 2.6 times below the `0.10` limit.
- Only `108/81920` outputs differ from exact-reciprocal finalization, all by exactly 1 Q8.8 LSB or less.

For a stricter RTL target, use **16 LUT entries and 2 NR iterations**:

- `512` ROM bits and 6-cycle latency.
- No final-output differences from exact reciprocal were observed in this data set.
- Maximum reciprocal relative error was `8.43e-7`.

The stricter verification recommendation for the selected 32x1 RTL is:

- Reciprocal maximum relative error `<=2.5e-4` on the full nonzero `U9.23` corner sweep used by verification.
- Candidate final output differs from exact-reciprocal finalization by at most 1 Q8.8 LSB.
- Project-level `MAE<=0.01` and `MaxAE<=0.05`, tighter than the external acceptance limits while still met by the measured result.
- Exact checkpoint matching for normalized mantissa, exponent, seed index/value, NR iterate, zero flag, and `out_valid`.

## Corner Cases

The table shows the recommended 32-entry, 1-iteration result.

| Input | `l` hex | Normalized / exponent | Exact reciprocal | NR reciprocal | Behavior |
|---|---:|---:|---:|---:|---|
| Zero | `00000000` | `00000000 / 0` | undefined | `00000000` | `divide_by_zero=1`, valid after 4 cycles |
| 1.0 | `00800000` | `80000000 / 0` | `80000000` | `7FF83E87` | Lower edge |
| Just below 2.0 | `00FFFFFF` | `FFFFFF00 / 0` | `40000040` | `3FFEFC35` | Top LUT interval |
| 2.0 | `01000000` | `80000000 / 1` | `40000000` | `3FFC1F43` | Exponent right shift |
| Just below 256 | `7FFFFFFF` | `FFFFFFFE / 7` | `00800000` | `007FFDF7` | Baseline upper neighborhood |
| 256.0 | `80000000` | `80000000 / 8` | `00800000` | `007FF83E` | Baseline nominal maximum |
| U32 maximum | `FFFFFFFF` | `FFFFFFFF / 8` | `00400000` | `003FFEFB` | Full-container upper edge |

The zero transaction is not dropped. It produces a deterministic zero result and error flag with the same fixed valid latency as nonzero inputs.
