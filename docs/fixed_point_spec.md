# Fixed-Point Spec v0.3 Numerical Closure

Status: model-side numerical contract for RTL alignment. The exp and online-softmax update rules below are frozen for the current baseline. Reciprocal remains the current exact integer oracle in this revision and is explicitly pending alignment to the future RTL Newton-Raphson implementation.

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
| Scaled score | `S32.16` container | 48 | Baseline v0.3 score is `raw_dot >>> 3`, binary point stays at 16. Current `fa_score_pipe` still emits unscaled raw dot; scale insertion is pending. |
| Softmax score / running max `m` | signed low 24 bits, `S8.16` | 24 | Consume `scaled_score[23:0]` as two's-complement before max/update. Initialize `m` from the first valid wrapped score. |
| Exp input `score - m_new` | signed `S*.16` | 24 | Evaluate the low signed 24-bit input on `[-16.0,0.0]`; values below `-16.0` produce zero. |
| Exp output `p` / `alpha` | `U1.23` | 24 | 33 rounded anchors at 0.5 spacing with integer linear interpolation. |
| Denominator `l` | `U9.23` | 32 | Range covers `[0, 256]` with guard up to `<512`. Initialize to 0. |
| Weighted accumulator `acc[d]` | `S17.31` | 48 | Accumulates `sum(exp * V)` before final divide. One accumulator per output dimension. |
| Reciprocal `recip_l` | `U1.31` | 32 | Represents `1/l` in `[1/256, 1]`. Saturate/flag if `l==0`, though valid causal rows should have `l>0`. |
| Final product `acc*recip_l` | internal wide | >=80 | Product has 62 fractional bits before output quantization. |
| O quantized | `S8.8` | 16 | Round half-away-from-zero and saturate to int16 for v0.3 integer finalization. |

## v0.3 Minimum Numerical Contract

This section is the smallest contract needed for the baseline `S=256,D=64,batch=1,head=1,causal,BK=32,scale=1/8` flow. It is intentionally narrower than a final v1.0 contract.

### Score and Scale

- `REG_SCALE=32` denotes the fixed baseline attention scale `1/8`. Programmable scale values are out of scope for v0.3.
- `raw_dot` is the signed 48-bit `S32.16` accumulation of 64 exact `S16.16` products.
- Baseline scaled score is the signed arithmetic shift `score_s32_16 = raw_dot >>> 3`. This is truncation toward negative infinity for negative two's-complement values.
- Online softmax consumes `score = signed(score_s32_16[23:0])`. The independent floating-point regression reference must apply the same low-24 wrapping before ideal softmax.
- Mask-invalid scores must be gated before row max, denominator, and accumulator updates. A finite debug sentinel may be printed, but it must not update `m`, `l`, or `acc`.

### Exp Input and Output

- Exp input is the signed low-24 `S*.16` delta.
- For `x >= 0`, output exactly `24'h800000`. For `x < -16.0`, output zero. The exact `x=-16.0` anchor is `24'h000001`.
- Freeze 33 anchors for `x_i=-i/2`, `i=0..32`:

```text
Y[i] = round(exp(-i/2) * 2^23)
```

- Between adjacent anchors, use the full 16-bit fractional score grid. With `step=2^15`, `offset=(-x)-i*step`, and `0 < offset < step`:

```text
drop = ((Y[i] - Y[i+1]) * offset + 2^14) // 2^15
exp  = Y[i] - drop
```

- This replaces the old single linear tail from `-4` to `-16`, which accumulated excessive probability mass for repeated scores near `-8`.

### Reciprocal

- Reciprocal input `l` is `U9.23` and must be nonzero for valid causal baseline rows.
- Reciprocal output is `U1.31`.
- The v0.3 reference integer formula is:

```text
recip_u1_31 = round_half_away_from_zero((2^31 * 2^23) / l_u9_23)
```

- Exact examples already frozen in debug files include `l=00800000 -> recip=80000000` and `l=01000000 -> recip=40000000`.
- This revision intentionally keeps the exact integer oracle above. It is not an RTL cost model. Replacing it with a LUT/NR approximation is deferred until the RTL Newton-Raphson contract is available, so exp/higher-score closure and reciprocal approximation are not changed simultaneously.

### Final O Quantization

- Final product uses `acc_s17_31 * recip_u1_31`, with 62 fractional bits before output quantization.
- The v0.3 reference integer output is:

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

v0.3 RTL target:

1. Multiply each `q[k] * k[k]` exactly in `S16.16`.
2. Accumulate 64 products in signed 48-bit.
3. Apply scale `1/8` by signed arithmetic right shift 3: `raw_dot >>> 3`.
4. Keep the scaled score in signed 48-bit with 16 fractional bits.

Open item: non-baseline `REG_SCALE` values must be aligned separately. `golden_model.py` uses `scale_int=32` for Q8.8 `1/8`; current scheduler smoke tests pass `16'h0100` but do not consume it. For v0.3, RTL should treat the baseline as fixed `REG_SCALE=32` and `raw_dot >>> 3`.

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

The scalar integer oracle specializes that equation without changing its meaning:

- `score == m`: `alpha=p=1`, add one unit to `l`, and add `V<<23` to each accumulator lane.
- `score < m`: `alpha=1`, `p=exp(score-m)`, then add `p` and `V*p`.
- `score > m`: this is a generic path for every positive delta, not an exact-point special case. Set `alpha=exp(m-score)` and `p=1`, rescale the old state, add the new term, and update `m=score`:

```text
l_new      = wrap_u32((l_old * alpha >> 23) + (1 << 23))
acc_new[d] = wrap_s48(wrap_s48(acc_old[d] * alpha >> 23)
                      + (V[j,d] << 23))
m_new      = score
```

The required higher-score regression points include `+0.5`, `+1.5`, and `+2.0`, plus a transition whose two source scores cross the signed low-24 wrap boundary.

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

## Exp PWL v0.3

The complete anchor vector, from `x=0` through `x=-16` in `-0.5` steps, is:

```text
800000 4DA2CC 2F16AC 1C8F87 1152AB 0A81C3 065F6C 03DD82
02582B 016C05 00DCCA 0085EA 005139 003144 001DE1 001220
000AFE 0006AB 00040B 000274 00017D 0000E7 00008C 000055
000034 00001F 000013 00000C 000007 000004 000003 000002
000001
```

All between-anchor inputs use the integer interpolation formula in "Exp Input and Output". There are no unsupported holes and no separate long-tail segment. A repeated `-8` risk vector must therefore accumulate `p=0x000AFE` per term rather than the old long-tail value.

The model regression gate is causal `S=64,D=64`, seeds `100,101,102`, with every seed required to meet:

```text
MAE   <= 0.03
MaxAE <= 0.10
```

An `S=256,D=64` single-seed run is recommended as an extended check when runtime permits.

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

## Reciprocal Oracle Pending RTL NR Alignment

- Input is nonzero `U9.23`; output is `U1.31`.
- The model continues to use the exact integer formula `round((2^31 * 2^23) / l_u9_23)` and wraps the result to 32 bits.
- No reciprocal LUT, seed quantization, or Newton-Raphson error is introduced in this revision.
- When the RTL NR datapath is ready, its seed rule, iteration count, narrowing points, and error bounds must be frozen in a separate change and compared against this oracle.

## Rounding and Saturation

v0.3 project rule:

- Addition/subtraction: compute in the destination container width when possible; saturate only when narrowing.
- Online `l*alpha` and `acc*alpha` rescaling uses integer `>>23` truncation before destination-width wrapping.
- Final output narrowing uses round-to-nearest with half-away-from-zero.
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
- Signed low-24 score wrapping before online softmax.
- Exp PWL interpolation error relative to ideal exp.
- `l` and `acc` rescale truncation and container wrapping.
- Future RTL reciprocal NR error relative to the current exact oracle.
- Final O rounding and saturation.
- Mask handling at tile boundaries.

## Items Not Frozen

These items remain open after the model-side numerical closure:

- RTL microarchitecture for implementing the frozen 33-anchor exp contract.
- Reciprocal NR seed, iteration count, narrowing points, and accepted error.
- Bit-exact Python/RTL alignment for all rounding and wrapping points.
- Whether `l`/`acc` can be reduced below 32/48 bits while preserving MAE and MaxAE targets.
- Whether non-default `REG_SCALE` values are supported beyond the fixed `REG_SCALE=32` baseline.
