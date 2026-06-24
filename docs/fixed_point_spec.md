# Fixed-Point Spec v0.2 Draft

Status: v0.2 minimum numerical contract for RTL bring-up, full-row vector reproducibility, and PPA exploration. This is still not the final v1.0 bit-exact numerical contract. The current `golden_model.py` uses FP32 for several softmax state variables to model a wide fixed-point datapath. The formats below should unblock RTL module sizing and debug dumps; v1.0 must be frozen after fixed-point sweep and RTL/golden bit matching.

## Baseline

- Shape: `S=256`, `D=64`, batch `1`, head `1`.
- Q/K/V input: signed int16 Q8.8.
- O output: signed int16 Q8.8.
- Attention scale: `1/sqrt(64) = 1/8`.
- Default K/V tile: `BK=32`.
- Causal mask: if `causal_en=1`, score `(q=i, k=j)` is valid only when `j <= i`.
- Invalid masked scores must not update `m`, `l`, or `acc`.

## Q Notation

This spec uses `S<I>.<F>` for signed fixed point and `U<I>.<F>` for unsigned fixed point. `I` includes the sign bit for signed formats. Total width is `I + F`.

Examples:

- Q8.8 input is `S8.8`, 16-bit, range `[-128.0, 127.99609375]`.
- `U1.23`, 24-bit, represents `[0, 1.99999988]`; exp values use `[0, 1]`.

## Proposed Datapath Formats

| Signal | Proposed format | Width | Notes |
|---|---:|---:|---|
| Q/K/V | `S8.8` | 16 | External memory and vector files. |
| Single product `q*k` | `S16.16` | 32 | Exact product of two Q8.8 values. |
| Raw dot `sum_64(q*k)` | `S32.16` container | 48 | Current RTL `fa_dot_pe` accumulates into signed 48-bit. Effective needed integer range is smaller, but 48-bit is safe. |
| Scaled score | `S32.16` container | 48 | Baseline v0.2 score is `raw_dot >>> 3`, binary point stays at 16. Current `fa_score_pipe` still emits unscaled raw dot; scale insertion is pending. |
| Running max `m` | `S32.16` container | 48 | One value per query row. Initialize to negative infinity sentinel. |
| Exp input `score - m_new` | clamp to `S8.8` | 16 | Clamp to `[-16.0, 0.0]` before LUT. Values below `-16.0` may output zero. |
| Exp output `p` / `alpha` | `U1.23` | 24 | `exp(0)=1.0` encoded as `1 << 23`. Current Python LUT uses FP32 and default 4096 entries; RTL LUT/PWL is pending. |
| Denominator `l` | `U9.23` | 32 | Range covers `[0, 256]` with guard up to `<512`. Initialize to 0. |
| Weighted accumulator `acc[d]` | `S17.31` | 48 | Accumulates `sum(exp * V)` before final divide. One accumulator per output dimension. |
| Reciprocal `recip_l` | `U1.31` | 32 | Represents `1/l` in `[1/256, 1]`. Saturate/flag if `l==0`, though valid causal rows should have `l>0`. |
| Final product `acc*recip_l` | internal wide | >=80 | Product has 62 fractional bits before output quantization. |
| O quantized | `S8.8` | 16 | Round half-away-from-zero and saturate to int16 for v0.2 integer finalization. |

## v0.2 Minimum Numerical Contract

This section is the smallest contract needed for the baseline `S=256,D=64,batch=1,head=1,causal,BK=32,scale=1/8` flow. It is intentionally narrower than a final v1.0 contract.

### Score and Scale

- `REG_SCALE=32` denotes the fixed baseline attention scale `1/8`. Programmable scale values are out of scope for v0.2.
- `raw_dot` is the signed 48-bit `S32.16` accumulation of 64 exact `S16.16` products.
- Baseline scaled score is the signed arithmetic shift `score_s32_16 = raw_dot >>> 3`. This is truncation toward negative infinity for negative two's-complement values.
- Mask-invalid scores must be gated before row max, denominator, and accumulator updates. A finite debug sentinel may be printed, but it must not update `m`, `l`, or `acc`.

### Exp Input and Output

- Exp input is `delta = score - m_new` in the score container, interpreted as `S*.16`.
- Clamp the real delta to `[-16.0, 0.0]`.
- Quantize/narrow the clamped value to signed `S8.8` for LUT/PWL addressing. For v0.2 debug points, exact mappings are required: `0.0 -> 16'h0000`, `-0.5 -> 16'hFF80`, `-1.0 -> 16'hFF00`, `-2.0 -> 16'hFE00`, `-4.0 -> 16'hFC00`, and `<= -16.0 -> 16'hF000`.
- Exp output is unsigned `U1.23`. `exp(0)` must be exactly `24'h800000`; clamped inputs `<= -16.0` produce zero for the bring-up contract.
- Generic exp may use either the current Python reference shape, a 4096-entry uniform LUT on `[-16,0]` with linear interpolation, or an RTL LUT/PWL candidate. Non-debug-point error is a v0.2 measurement item, not a v1.0 bit-exact promise; debug dumps must record `exp_mode` and report any MAE/MaxAE or ULP tolerance used.

### Reciprocal

- Reciprocal input `l` is `U9.23` and must be nonzero for valid causal baseline rows.
- Reciprocal output is `U1.31`.
- The v0.2 reference integer formula is:

```text
recip_u1_31 = round_half_away_from_zero((2^31 * 2^23) / l_u9_23)
```

- Exact examples already frozen in debug files include `l=00800000 -> recip=80000000` and `l=01000000 -> recip=40000000`.
- The Python full-row generator may use the current LUT plus one Newton-Raphson-shaped approximation for `O_q88` generation. RTL may use LUT-only or LUT+NR during PPA exploration, but it must label `recip_mode`; bit-exact reciprocal approximation is a v1.0 item.

### Final O Quantization

- Final product uses `acc_s17_31 * recip_u1_31`, with 62 fractional bits before output quantization.
- The v0.2 reference integer output is:

```text
o_q88_raw = round_half_away_from_zero((acc_s17_31 * recip_u1_31) / 2^54)
O_q88     = saturate_int16(o_q88_raw)
```

- Saturation limits are `-32768` and `32767`, representing `[-128.0, 127.99609375]`.
- NumPy-based FP32 `O_ref` may still use NumPy's default rounding behavior; exact halfway ties must be aligned before v1.0.

## Score Path

Current RTL state:

- `fa_dot_pe` and `fa_score_pipe` output a signed 48-bit raw dot product.
- That raw dot is a Q16.16 accumulated value, not yet multiplied by `1/8`.

v0.2 RTL target:

1. Multiply each `q[k] * k[k]` exactly in `S16.16`.
2. Accumulate 64 products in signed 48-bit.
3. Apply scale `1/8` by signed arithmetic right shift 3: `raw_dot >>> 3`.
4. Keep the scaled score in signed 48-bit with 16 fractional bits.

Open item: non-baseline `REG_SCALE` values must be aligned separately. `golden_model.py` uses `scale_int=32` for Q8.8 `1/8`; current scheduler smoke tests pass `16'h0100` but do not consume it. For v0.2, RTL should treat the baseline as fixed `REG_SCALE=32` and `raw_dot >>> 3`.

## v1.0 Freeze Candidates

Baseline v1.0 should freeze the smallest contract needed for RTL/golden bit matching:

- Whether v1.0 remains fixed to `REG_SCALE=32` or supports other scale values.
- Whether v1.0 keeps score scaling as `raw >>> 3` or introduces a rounded programmable multiply/shift path.
- Mask-invalid scores must be gated before any row max, denominator, or accumulator update. Invalid scores must not participate in `m`, `l`, or `acc`, even as a finite negative sentinel.

Recommendation: freeze the baseline around `REG_SCALE=32` plus `raw >>> 3` first, then defer programmable scale behavior until after causal baseline closure.

## Online Softmax Update

For each valid score in a K/V tile:

```text
m_new   = max(m_old, score)
alpha   = exp(m_old - m_new)
p       = exp(score - m_new)
l_new   = l_old * alpha + p
acc_new = acc_old * alpha + p * V[j, :]
m       = m_new
l       = l_new
acc     = acc_new
```

Tile-level update is also allowed:

```text
m_new   = max(m_old, max(score_tile_valid))
alpha   = exp(m_old - m_new)
p[j]    = exp(score[j] - m_new) for valid j
l_new   = l_old * alpha + sum(p[j])
acc_new = acc_old * alpha + sum(p[j] * V[j, :])
```

Both forms must produce the same fixed-point interpretation for valid elements. Masked elements must be ignored, not represented as a large finite value that can enter reductions. If implementation convenience requires a sentinel, use it only before a `mask_valid` gate.

### Bring-Up Equal-Score Subset

For early RTL bring-up, include a two-update subset where the second effective valid score is exactly equal to the current running max `m`.

In that subset:

1. First effective valid score establishes the state:

```text
m   = score
l   = 1 << 23
acc = V[first_valid, :] << 23
```

2. When the next valid score satisfies `score == m`, the online softmax update must use `exp(0)` exactly:

```text
p       = 1 << 23
alpha   = 1 << 23
l_new   = l_old + (1 << 23)
acc_new = acc_old + (V[second_valid, :] << 23)
m_new   = m_old
```

The debug skeleton records this as `p=00800000`, `alpha=00800000`, `l_delta=00800000`, and `acc_delta=V<<23`. This rule is independent of the eventual exp LUT interpolation choice because `exp(0)` must be exact.

### Bring-Up Vector First/Equal Subset

The 64-lane accumulator version uses the same online softmax scalar state for the whole query row:

- `m` is shared by all 64 output lanes.
- `l` is shared by all 64 output lanes.
- `acc[0:63]` are independent signed `S17.31` lanes.

For a first valid score of `0.0`, the vector accumulator initializes each lane independently:

```text
m      = 0
l      = 1 << 23
acc[d] = V0[d] << 23
```

The manual vector checkpoint `test_vectors/debug/softmax_vec_first_equal/expected.txt` freezes three nonzero lanes for `D=64`:

```text
V0[0]  = +1.0 -> acc0_first  = 000080000000
V0[1]  = -1.0 -> acc1_first  = FFFF80000000
V0[63] = +2.0 -> acc63_first = 000100000000
```

For the second valid equal score, `p=alpha=1<<23`, so `m` remains shared and unchanged, `l` becomes `01000000`, and each lane adds `V2[d] << 23` independently:

```text
V2[0]  = +0.5 -> acc0_new  = 0000C0000000
V2[1]  = +1.0 -> acc1_new  = 000000000000
V2[63] = -1.0 -> acc63_new = 000080000000
```

## Exp Approximation Draft

Default Python model:

- Range: `x in [-16.0, 0.0]`.
- Entries: 4096.
- Method: uniform LUT with linear interpolation.

RTL v0.1 recommendation:

- Input source: `score - m_new` from the score path, normally a signed `S*.16` value such as the 48-bit `S32.16` score container.
- LUT/PWL input contract draft: convert the `S*.16` delta to the exp input domain by clamping the real value to `[-16.0, 0.0]`, then narrowing/quantizing to `S8.8` for address/interpolation generation. A delta of `0.0` must map exactly to `16'h0000`; a delta of `-1.0` must map exactly to `16'hFF00`; values `<= -16.0` clamp to `16'hF000`.
- Output: `U1.23`.
- Bring-up constants:
  - `exp(0) = 1 << 23 = 8388608 = 00800000`.
  - `exp(-1) = round(exp(-1) * 2^23) = 3085996 = 002F16AC`.
  - `exp(x <= -16.0) = 0`.
- Initial implementation may use LUT only or LUT plus interpolation. The exact table size and interpolation rule are not frozen.

### Bring-Up Exp LUT v0.2

The current RTL bring-up table freezes a few exact S*.16 debug points while the final LUT/PWL/interpolation scheme remains open:

| Real input | S*.16 low-24 hex | U1.23 output |
|---:|---:|---:|
| `0.0` | `000000` | `800000` |
| `-0.5` | `FF8000` | `4DA2CC` |
| `-1.0` | `FF0000` | `2F16AC` |
| `-2.0` | `FE0000` | `1152AB` |
| `-4.0` | `FC0000` | `02582B` |
| `<= -16.0` | `F00000` or lower | `000000` |

Unsupported between-table points may still return zero in v0.2; do not treat this table as the final exp implementation.

### Pending v1.0 Freeze Checklist

The v1.0 freeze must move beyond exact-point bring-up constants and lock the row-level numerical contract:

- Exp LUT/PWL: input clamp range, `S*.16` to address-domain quantization, table/PWL segmentation, interpolation rule, and exact behavior between `0`, `-0.5`, `-1`, `-2`, `-4`, and the `<= -16` clamp.
- Reciprocal: input range, LUT size or seed rule, whether Newton-Raphson is mandatory, output rounding, and `l==0` handling.
- Rounding/saturation: signed shift tie rule, multiply/add narrowing points, final `S8.8` saturation limits, and Python/RTL tie consistency.
- Error thresholds: row-level MAE/MaxAE targets for `O_q88`, allowed exp/recip ULP error, and bit-exact-only subsets such as deterministic scoreboard sentinels.

Generated regression input:

- `test_vectors/cases/random_full_row_seed20240623_*` is the current reproducible full `S=256,D=64` causal random baseline. Use it to exercise full-row scoreboard plumbing and collect MAE/MaxAE against FP32. Do not treat its `O_q88` as a frozen bit-exact RTL contract until the exp, reciprocal, and rounding items above are closed.

Required draft row behavior:

| Real delta | S8.8 exp input | U1.23 output | Notes |
|---:|---:|---:|---|
| `0.0` | `0000` | `00800000` | Exact one; no approximation error allowed. |
| `-1.0` | `FF00` | `002F16AC` | Temporary bring-up constant using rounded ideal exp. |
| `<= -16.0` | `F000` after clamp | `00000000` | Underflow clamp for baseline debug. |

The final exp implementation may be pure LUT, LUT plus interpolation, or PWL. Table size, interpolation/PWL coefficients, and any rounding between `S*.16` and `S8.8` remain v1.0 freeze items. Until frozen, debug dumps should record the exp mode and must at least match the exact rows above.

### Bring-Up Lower-By-1 Subset

This subset checks the first non-equal valid update where the second score is lower than the current running max by exactly `1.0`.

Initial state after the first valid score:

```text
m       = 0
l       = 1 << 23
acc_old = V0 << 23
```

For a second valid `score = -1.0`, `m_new = m_old = 0`, `alpha = exp(0)`, and:

```text
p       = exp(-1) = 002F16AC
l_new   = (1 << 23) + p
acc_new = acc_old + V1 * p
```

The accumulator target remains `S17.31` because `V` is signed `S8.8` and `p` is `U1.23`.

Exact integer example for `V0 = 1.0` and `V1 = 2.0`:

```text
V0_q88          = 256
V1_q88          = 512
exp0_u1_23      = 8388608  = 00800000
exp_neg1_u1_23  = 3085996  = 002F16AC
l_new_u9_23     = 11474604 = 00AF16AC
acc_old_s17_31  = 2147483648 = 000080000000
acc_delta_s17_31= 1580029952 = 00005E2D5800
acc_new_s17_31  = 3727513600 = 0000DE2D5800
```

### Bring-Up Raise-By-1 Subset

This subset checks the first valid update where the second score is higher than the current running max by exactly `1.0`.

Initial state after the first valid score:

```text
m       = 0
l       = 1 << 23
acc_old = V0 << 23
```

For a second valid `score = +1.0`, `m_new = score`, `alpha = exp(m_old - m_new) = exp(-1)`, and:

```text
alpha   = exp(-1) = 002F16AC
p       = exp(0)  = 00800000
l_new   = ((1 << 23) * alpha >> 23) + (1 << 23)
acc_new = (((V0 << 23) * alpha) >> 23) + (V1 << 23)
```

Exact integer example for `V0 = 1.0` and `V1 = 2.0`:

```text
V0_q88                          = 256
V1_q88                          = 512
alpha_exp_neg1_u1_23            = 3085996  = 002F16AC
p_exp0_u1_23                    = 8388608  = 00800000
l_old_times_alpha_shifted_u9_23 = 3085996  = 002F16AC
l_new_u9_23                     = 11474604 = 00AF16AC
acc_old_s17_31                  = 2147483648 = 000080000000
acc_old_rescaled_s17_31         = 790014976  = 00002F16AC00
acc_new_contrib_s17_31          = 4294967296 = 000100000000
acc_new_s17_31                  = 5084982272 = 00012F16AC00
```

The corresponding manual expected file is `test_vectors/debug/softmax_raise_by_one/expected.txt`.

## Reciprocal Approximation Draft

Default Python model:

- Range: `l in [0.5, 260.0]`.
- Entries: 1024.
- Method: uniform LUT with linear interpolation and optional one Newton-Raphson refinement.

RTL v0.2 recommendation:

- Input: `U9.23`.
- Output: `U1.31`, using `round_half_away_from_zero((2^31 * 2^23) / l_u9_23)` for reference integer debug values.
- Clamp range for LUT address generation to `[0.5, 260.0]`.
- Apply one Newton-Raphson iteration if area/timing allows:

```text
y1 = y0 * (2 - l * y0)
```

Open item: whether NR is mandatory is not frozen. If RTL skips NR for bring-up, debug dumps must mark `recip_mode=lut_only`.

## Rounding and Saturation

v0.2 project rule:

- Addition/subtraction: compute in the destination container width when possible; saturate only when narrowing.
- Multiplication: keep full product internally, then round when reducing fractional bits.
- Narrowing right shifts: use round-to-nearest with half-away-from-zero for signed integer debug/finalization values.
- Final O quantization: `round_half_away_from_zero((acc_s17_31 * recip_u1_31) / 2^54)`, then saturate to signed int16 range `[-32768, 32767]`.

Compatibility note: `golden_model.py::float_to_q88` currently uses NumPy `round`, which is ties-to-even. Exact half-way cases are rare in random vectors but must be resolved before bit-exact v1.0.

## Mask and Negative Infinity

- Golden causal rule: valid iff `k_index <= q_index`.
- For invalid positions, do not update row max, denominator, or accumulator.
- `NEG_LARGE` may be used for score debug visibility, but it must not be allowed to win a max or add exp mass.
- For row `i=0` in causal mode, only `k=0` is valid. Therefore `l` must end nonzero and `O[0, :]` should equal `V[0, :]` within quantization/softmax approximation.

### `causal_i0` Scalar Pipeline Checkpoint

The generated debug subset `test_vectors/debug/causal_i0` freezes a narrow scheduler/score/softmax scalar checkpoint for `q=0`, `dim=0`.

- `Q[0, :]` and `K[0, :]` are all zero, so the scaled score for `k=0` is exactly `0`, encoded as `000000000000` in `S32.16`.
- `V[0][0] = 0x0100` (`+1.0` in Q8.8), so the first valid accumulator update is `V[0][0] << 23 = 000080000000` in `S17.31`.
- After accepting `k=0`, the expected state is `m=000000000000`, `l=00800000`, `acc_dim00=000080000000`.
- For `q=0`, `k=1` is masked. Even though its debug score is also zero, it must not update `m`, `l`, or `acc_dim00`; those fields remain equal to the after-`k=0` state.

## Finalization

After all K/V tiles for a query row:

```text
recip_l = approx_recip(l)
O[d]    = quant_q88(acc[d] * recip_l)
```

With the proposed formats:

- `acc` is `S17.31`.
- `recip_l` is `U1.31`.
- Product has 62 fractional bits.
- To produce Q8.8, right shift by 54 after rounding, then saturate to int16.

## Error Sources to Track

- Q/K/V input quantization to Q8.8.
- Dot-product scale rounding.
- Score/m narrowing before exp LUT.
- Exp approximation and output quantization.
- `l` and `acc` multiply/add rounding.
- Reciprocal approximation.
- Final O rounding and saturation.
- Mask handling at tile boundaries.

## Items Not Frozen

These items must remain marked draft until sweep data exists:

- Exact exp LUT size and whether interpolation is used in RTL.
- Exact reciprocal LUT size and whether NR is mandatory.
- Exact rounding tie rule across Python and RTL.
- Whether exp output should be `U1.23` or a smaller width such as `U1.15` for area.
- Whether `l`/`acc` can be reduced below 32/48 bits while preserving MAE and MaxAE targets.
- Whether non-default `REG_SCALE` values are supported beyond the fixed `REG_SCALE=32` baseline.
