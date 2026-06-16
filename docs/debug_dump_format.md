# Debug Dump Format v0.1

Status: minimal text dump format for comparing RTL against Python fixed/golden state. This is a proposed format. `scripts/generate_corner_vectors.py` currently emits initial `causal_i0` and `non_causal_smoke` debug subsets for `q_index=00`.

## Directory Layout

Recommended location:

```text
test_vectors/debug/<case_name>/
```

Minimum files:

```text
meta.txt
score_tile.hex
mask_valid.hex
m_l_after_tile.hex
acc_after_tile.hex
recip_l.hex
O_q88.hex
```

All multi-dimensional files are row-major. All integer fields are uppercase hex without `0x`.

## `meta.txt`

ASCII key/value file:

```text
case=test_000
S=256
D=64
BK=32
causal=1
score_format=S32.16
exp_format=U1.23
l_format=U9.23
acc_format=S17.31
recip_format=U1.31
o_format=S8.8
rounding=draft
recip_mode=lut_nr
```

If RTL is using a temporary approximation, record it here rather than hiding the mismatch.

For scalar pipeline bring-up, `meta.txt` may also carry exact single-dimension checkpoints. The current `causal_i0` subset uses:

```text
pipeline_scalar_dim=00
expected_after_k0_score=000000000000
expected_after_k0_m=000000000000
expected_after_k0_l=00800000
expected_after_k0_acc_dim00=000080000000
expected_after_k1_masked_valid=0
expected_after_k1_masked_score=000000000000
expected_after_k1_masked_m=000000000000
expected_after_k1_masked_l=00800000
expected_after_k1_masked_acc_dim00=000080000000
expected_after_k1_masked_rule=no_update_from_after_k0
```

The `expected_after_k*` keys are intended for narrow scheduler/score/softmax scalar pipeline TBs that do not yet compare full `acc_after_tile.hex`. They are a frozen subset of the same fixed-point interpretation used by the dump files.

## `score_tile.hex`

One line per score in tile traversal order:

```text
q_index kv_tile k_index score_hex
```

- `q_index`: 2 hex digits, `00..FF`.
- `kv_tile`: 2 hex digits.
- `k_index`: 2 hex digits.
- `score_hex`: 12 hex digits, signed 48-bit `S32.16` scaled score.

For current score-pipe debug before scale insertion, set `score_format=raw_dot_S32.16_unscaled` in `meta.txt`.

## `mask_valid.hex`

One line per score in the same order as `score_tile.hex`:

```text
q_index kv_tile k_index valid
```

- `valid` is `1` if the score participates in online softmax.
- `valid` is `0` if masked or outside `S`.

For causal baseline, `valid = (k_index <= q_index)`.

## `m_l_after_tile.hex`

One line after each completed K/V tile for each query row:

```text
q_index kv_tile m_hex l_hex
```

- `m_hex`: 12 hex digits, signed 48-bit `S32.16`.
- `l_hex`: 8 hex digits, unsigned 32-bit `U9.23`.

`kv_tile` is the tile just consumed. For `S=256`, `BK=32`, valid tile ids are `00..07`.

## `acc_after_tile.hex`

One line per output dimension after each completed K/V tile:

```text
q_index kv_tile dim acc_hex
```

- `dim`: 2 hex digits, `00..3F`.
- `acc_hex`: 12 hex digits, signed 48-bit `S17.31`.

This file is intentionally large: `256 * 8 * 64 = 131072` lines for full baseline. For early debug, dumping one row or one tile is acceptable if `meta.txt` records the subset.

## `recip_l.hex`

One line per query row after final denominator is available:

```text
q_index l_hex recip_l_hex
```

- `l_hex`: 8 hex digits, unsigned 32-bit `U9.23`.
- `recip_l_hex`: 8 hex digits, unsigned 32-bit `U1.31`.

## `O_q88.hex`

Use the same format as normal output vectors:

- 16384 lines for full baseline.
- Four uppercase hex digits per line.
- Row-major `[256, 64]`.
- Signed int16 Q8.8.

For partial debug, prefer a separate file name such as `O_q88_row_00.hex` and document the subset in `meta.txt`.

## Current Generated Debug Subset

`scripts/generate_corner_vectors.py` writes:

```text
test_vectors/debug/causal_i0/meta.txt
test_vectors/debug/causal_i0/score_tile.hex
test_vectors/debug/causal_i0/mask_valid.hex
test_vectors/debug/causal_i0/m_l_after_tile.hex
test_vectors/debug/non_causal_smoke/meta.txt
test_vectors/debug/non_causal_smoke/score_tile.hex
test_vectors/debug/non_causal_smoke/mask_valid.hex
test_vectors/debug/non_causal_smoke/m_l_after_tile.hex
test_vectors/debug/non_causal_smoke/acc_after_tile.hex
```

These are skeleton subsets, not full baseline dumps.

Manual debug notes may also exist under:

```text
test_vectors/debug/softmax_lower_by_one/expected.txt
test_vectors/debug/softmax_lower_by_one/final_expected.txt
test_vectors/debug/softmax_lower_by_half/expected.txt
test_vectors/debug/softmax_raise_by_one/expected.txt
test_vectors/debug/softmax_vec_first_equal/expected.txt
test_vectors/debug/softmax_vec_first_equal/final_expected.txt
test_vectors/debug/softmax_vec_first_equal/pipeline_expected.txt
test_vectors/debug/causal_i0/expected.txt
test_vectors/debug/causal_i0/final_expected.txt
test_vectors/debug/causal_i0/pipeline_final_expected.txt
test_vectors/debug/q1_equal_two_valid/pipeline_final_expected.txt
test_vectors/debug/exp_lut_v02/expected.txt
test_vectors/debug/q1_delta_neg1/pipeline_final_expected.txt
test_vectors/debug/q1_delta_neg_half/pipeline_final_expected.txt
test_vectors/debug/q1_delta_neg2/pipeline_final_expected.txt
test_vectors/debug/q1_delta_neg4/pipeline_final_expected.txt
test_vectors/debug/row_scoreboard_s4_det/expected.txt
```

This file freezes the temporary bring-up constants for the first lower-score update: after an initial valid `m=0`, `l=1<<23`, `acc=V0<<23`, a second valid `score=-1.0` uses `p=round(exp(-1)*2^23)=002F16AC`, `l_new=00AF16AC`, and for `V0=1.0`, `V1=2.0`, `acc_new=0000DE2D5800` in `S17.31`. It is a hand-written scalar checkpoint, not a generated full-tile dump.

The raise-by-one file freezes the complementary max-raise update: after the same initial state, a second valid `score=+1.0` raises `m_new` and uses `alpha=round(exp(-1)*2^23)=002F16AC`, `p=1<<23`, `l_new=00AF16AC`, and for `V0=1.0`, `V1=2.0`, `acc_new=00012F16AC00` in `S17.31`. This is also a hand-written scalar checkpoint.

The `softmax_lower_by_half/expected.txt` file freezes a softmax generic lower delta v0.2 smoke: first `score=0,V0 lane00=1.0`, then second `score=-0.5,V1 lane00=2.0`. It uses the exp LUT v0.2 exact point `p=004DA2CC` for `exp(-0.5)`, so `l_new=(1<<23)+p=13476556` (`00CDA2CC`) and `acc_new=(1.0<<23)+(2.0*p)=4752513024` (`00011B459800`). This is not the final exp LUT/PWL contract and not a row-level golden.

The vector first/equal file freezes the first `D=64` accumulator branch checkpoint. `m` and `l` are shared per query row, while `acc[0:63]` are independent signed `S17.31` lanes. The file records `V0[0]=+1.0`, `V0[1]=-1.0`, `V0[63]=+2.0` for the first valid update (`acc=V0<<23`), then an equal-score update with `V2[0]=+0.5`, `V2[1]=+1.0`, `V2[63]=-1.0`. The frozen result is `l=01000000`, `acc[0]=0000C0000000`, `acc[1]=000000000000`, and `acc[63]=000080000000`.

The `softmax_vec_first_equal/final_expected.txt` file freezes the matching final datapath smoke for that vector checkpoint. It uses `l=2.0` (`l_u9_23_hex=01000000`) and `recip_l=0.5` (`recip_u1_31_hex=40000000`). The expected final output lanes are listed for all `D=64` lanes, with key checks `lane00=00C0`, `lane01=0000`, and `lane63=0080`. This file validates the narrow `l/acc[64] -> recip/out_quant -> O_q88` path for the equal-score vector case only; it is not a complete random row-level golden.

The `softmax_vec_first_equal/pipeline_expected.txt` file ties those two checkpoints together as a `softmax_vec -> finalize_vec` pipeline e2e smoke. It records the two input beats explicitly: `score0=0,V0` followed by `score1=0,V2`. The expected softmax handoff state is `m=000000000000`, `l=01000000`, and `acc[d]=(V0_q88[d]+V2_q88[d])<<23`; the finalize handoff uses `recip=40000000`. The key output lanes are `lane00=00C0`, `lane01=0000`, and `lane63=0080`, with `lane_count=64` and unspecified lanes defaulting to zero. This is a narrow pipeline alignment smoke for bring-up, not a randomized row-level golden or full softmax correctness contract.

The `causal_i0/expected.txt` file freezes the scheduler->score->V[64] softmax smoke checkpoint for `q=0,k=0`. It is derived from `test_vectors/cases/causal_i0_V.hex` row 0 and lists every `d=0..63` lane as:

```text
laneDD_v_q88_hex=<V[0][DD]>
laneDD_acc_s17_31_hex=<signed_q88(V[0][DD]) << 23>
```

`DD` is the decimal lane id `00..63`. Because causal row 0 has only `k=0` valid, the vector smoke can compare `score=000000000000`, `m=000000000000`, `l=00800000`, then all 64 accumulator lanes directly against this file after the first valid update. The key quick-check lanes are `lane00=000080000000`, `lane01=FFFF80000000`, `lane02=000040000000`, and `lane63=000000000000`.

The `causal_i0/final_expected.txt` file freezes the next finalization smoke checkpoint:

```text
l/acc[64] -> recip/out_quant -> O_q88
```

It uses the same `q=0,k=0` causal row. Since only `k=0` is valid, `l=1<<23` (`l_u9_23_hex=00800000`), the temporary reciprocal convention records `recip_l=1.0` as `recip_u1_31_hex=80000000`, and each final output lane is exactly `O_q88[d]=V0[d]`. This file is for narrow final path bring-up only. It is not a full random row-level golden and should not be used to validate general reciprocal, rounding, or multi-K softmax behavior.

The `causal_i0/pipeline_final_expected.txt` file ties the scheduler-driven smoke together as:

```text
scheduler -> score_pipe -> softmax_vec -> finalize_vec
```

It records the `q=0` causal path end to end: `Q0/K0` are all zero, so `k0` produces scaled score `000000000000`; `k1` is masked (`valid=0`) and must not update `m/l/acc`; the softmax handoff is `m=000000000000`, `l=00800000`, and `acc[d]=V0[d]<<23`; finalization uses `recip=80000000` and returns `O=V0`. Key output lanes are `lane00=0100`, `lane01=FF00`, `lane02=0080`, and `lane63=0000`, with `lane_count=64` and all lanes listed explicitly. This is a scheduler-driven final e2e smoke for stage alignment, not a complete `S=256` randomized golden.

The `q1_equal_two_valid/pipeline_final_expected.txt` file is the next scheduler-driven final smoke for the same path:

```text
scheduler -> score_pipe -> softmax_vec -> finalize_vec
```

It records a controlled `q=1` row where `k0` and `k1` are valid, `k2` is masked, and both valid scaled scores are exactly `000000000000`. After `k0`, online softmax has `l=00800000`; after equal-score `k1`, the final denominator is `l=01000000` and finalization uses `recip=40000000`. The expected output is `O=(V0+V1)/2`. Key output lanes are `lane00=00C0`, `lane01=0000`, and `lane63=0080`, with all `D=64` `laneDD_o_q88_hex` lines present for script checks. This file is a narrow q1/two-valid scheduler-driven final smoke, not a randomized row-level golden or a full softmax correctness contract.

The `softmax_lower_by_one/final_expected.txt` file freezes a single-lane final datapath smoke for `l=1+exp(-1)`. It reuses the lower-by-one accumulator checkpoint (`l_u9_23_hex=00AF16AC`, `acc=0000DE2D5800`) and records `recip_u1_31_hex=5D935411`, computed from the quantized denominator as `round((2^31*2^23)/l_u9_23)`. The expected output is `lane00_o_q88_hex=0145`. The final quantization tie rule is the recommended RTL rule, round-to-nearest with signed half-away-from-zero ties. The recorded lane is not itself a tie, but the file documents the rule that must be used when a final product lands exactly halfway.

These `final_expected.txt` files are final datapath smoke vectors. They are intentionally small, hand-written, bit-exact checkpoints for bring-up. They do not replace full generated `O_q88.hex` row comparisons, randomized softmax golden tests, or the eventual frozen exp/recip LUT contract.

### `exp_lut_v02`

- `expected.txt` freezes the current exact-point exp bring-up table: `0`, `-0.5`, `-1`, `-2`, `-4`, and the `<= -16` clamp.
- Inputs are recorded in S*.16 low-24 hex and outputs in U1.23 hex.
- This is not the final exp LUT/PWL/interpolation scheme; unsupported between-table points may still return zero until generic bucket mapping is added.

### `causal_i0`

- `subset=q_index=00 only` in `meta.txt`.
- `score_tile.hex` and `mask_valid.hex` cover all 256 K positions for `q=0`.
- `m_l_after_tile.hex` covers the 8 K/V tiles for `q=0`.
- `expected.txt` covers the vector accumulator checkpoint after valid `k=0`; use it when the smoke observes all `V[64]` lanes rather than the scalar `pipeline_scalar_dim=00` checkpoint in `meta.txt`.
- `final_expected.txt` covers the finalization smoke after that accumulator checkpoint; compare `l=00800000`, `recip_l=80000000`, and 64 `O_q88` lanes where `O_q88[d]=V0[d]`.
- `pipeline_final_expected.txt` covers the scheduler-driven final e2e smoke from `scheduler -> score_pipe -> softmax_vec -> finalize_vec`. It compares `k0` score `000000000000`, masked `k1` no-update behavior, final softmax `m/l/acc`, reciprocal `80000000`, and all 64 final `O_q88` lanes.
- For causal row 0, only `k=0` is valid. The first valid update must satisfy `m=scaled_score`, `l=1<<23`, and `acc=V<<23`. The corresponding hex values are recorded in `meta.txt`.
- Scalar pipeline TBs should set the observed accumulator dimension from `pipeline_scalar_dim=00`, then compare only the exact checkpoints below:
  - after `k=0`: `score=000000000000`, `m=000000000000`, `l=00800000`, `acc_dim00=000080000000`.
  - after `k=1`: `mask_valid=0`, `score=000000000000`, and `m/l/acc_dim00` must remain equal to the after-`k=0` values.
- Cross-check source files:
  - `score_tile.hex` line `00 00 00 000000000000` gives the `k=0` score.
  - `mask_valid.hex` line `00 00 01 0` proves `k=1` is masked.
  - `m_l_after_tile.hex` line for tile `00` must remain `00 00 000000000000 00800000`, because all `k=1..31` entries in tile 0 are masked for `q=0`.

### `q1_equal_two_valid`

- `pipeline_final_expected.txt` is hand-written for a controlled q1/two-valid scheduler-driven final smoke.
- The intended path is `scheduler -> score_pipe -> softmax_vec -> finalize_vec`.
- For `q=1`, `k0` and `k1` are valid and `k2` is masked. The frozen scaled scores for `k0` and `k1` are both `000000000000`.
- Compare the denominator checkpoints exactly:
  - after `k0`: `l=00800000`.
  - after `k1` and final: `l=01000000`.
  - final reciprocal: `recip=40000000`.
- The final expected output is `O=(V0+V1)/2`. Key lanes are `lane00_o_q88_hex=00C0`, `lane01_o_q88_hex=0000`, and `lane63_o_q88_hex=0080`.

### `q1_delta_neg1`

- `pipeline_final_expected.txt` is hand-written for a controlled q1 scheduler-driven final smoke.
- It drives `Q1[0]=0100`, `K0[0]=0000`, and `K1[0]=F800`, so k0 scaled score is zero and k1 scaled score is `FFFFFFFF0000` (`-1.0` in the softmax score domain).
- Causal mask still suppresses k2, so the row has two valid updates and one observed masked no-update point.
- The final softmax denominator is `00AF16AC`, reciprocal is `5D935411`, and lane00 output is `0145`; other lanes are held at zero. This proves the scheduler-driven lower-by-one bring-up branch, not a general exp LUT or random row golden.
- This is not generated by `scripts/generate_corner_vectors.py`, and it is not a random row-level golden. Use it only to align this narrow scheduler-driven final path.

### `q1_delta_neg_half`

- `pipeline_final_expected.txt` is hand-written for a controlled q1 scheduler-driven `-0.5` final smoke.
- It drives `Q1[0]=0100`, `K0[0]=0000`, and `K1[0]=FC00`, so k0 scaled score is zero and k1 has raw dot `-262144`, scaled score `FFFFFFFF8000` (`-0.5`), and softmax low24 `FF8000`.
- Causal mask still suppresses k2, so k2 must be observed as a masked no-update point.
- The exact bring-up constants are `exp(-0.5)=004DA2CC`, final `l=00CDA2CC`, lane00 accumulator `00011B459800`, reciprocal `4FACBF4E`, and lane00 final output `0161`; all other lanes are held at zero.
- This smoke is scheduler-driven and bit-exact only for the stated bring-up constants. It is still not the final exp/recip contract, not a randomized row-level golden, and not a full softmax correctness golden.

### `q1_delta_neg2`

- `pipeline_final_expected.txt` is hand-written for a controlled q1 scheduler-driven `-2.0` final smoke.
- It drives `Q1[0]=0100`, `K0[0]=0000`, and `K1[0]=F000`, so k0 scaled score is zero and k1 has raw dot `-1048576`, scaled score `FFFFFFFE0000` (`-2.0`), and softmax low24 `FE0000`.
- Causal mask still suppresses k2, so k2 must be observed as a masked no-update point.
- The exact bring-up constants are `exp(-2)=001152AB`, final `l=009152AB`, lane00 accumulator `0000A2A55600`, reciprocal `70BDF523`, and lane00 final output `011F`; all other lanes are held at zero.
- This smoke is scheduler-driven and bit-exact only for the stated bring-up constants. It is still not the final exp/recip contract, not a randomized row-level golden, and not a full softmax correctness golden.

### `q1_delta_neg4`

- `pipeline_final_expected.txt` is hand-written for a controlled q1 scheduler-driven `-4.0` final smoke.
- It drives `Q1[0]=0100`, `K0[0]=0000`, and `K1[0]=E000`, so k0 scaled score is zero and k1 has raw dot `-2097152`, scaled score `FFFFFFFC0000` (`-4.0`), and softmax low24 `FC0000`.
- Causal mask still suppresses k2, so k2 must be observed as a masked no-update point.
- The exact bring-up constants are `exp(-4)=0002582B`, final `l=0082582B`, lane00 accumulator `000084B05600`, reciprocal `7DB2A076`, and lane00 final output `0105`; all other lanes are held at zero.
- This smoke is scheduler-driven and bit-exact only for the stated bring-up constants. It is still not the final exp/recip contract, not a randomized row-level golden, and not a full softmax correctness golden.

### `row_scoreboard_s4_det`

- `expected.txt` is a deterministic row-level scoreboard expected pack for the same final path:

```text
scheduler -> score_pipe -> softmax_vec -> finalize_vec
```

- It records one controlled row, `q_index=03`, with `S_active=4` valid K entries and `D=64` output lanes. Scores are `0.0`, `-0.5`, `-2.0`, and `-4.0`, encoded as `000000000000`, `FFFFFFFF8000`, `FFFFFFFE0000`, and `FFFFFFFC0000`.
- The matching inputs are `test_vectors/cases/row_scoreboard_s4_det_Q.hex`, `row_scoreboard_s4_det_K.hex`, and `row_scoreboard_s4_det_V.hex`. They use the same flat `[256,64]` row-major Q/K/V hex layout as the other case vectors. `Q[3][0]=0100`; `K[0..3][0]` are `0000`, `FC00`, `F000`, and `E000`; and V rows `0..3` take their nonzero lane values from the `laneDD_v0_q88_hex` through `laneDD_v3_q88_hex` keys in `expected.txt`.
- The file lists all 64 `laneDD_o_q88_hex` lines so a row/full-row scoreboard can compare a complete D-lane row without requiring a full `S=256` golden dump.
- Key nonzero lanes are `00`, `01`, `02`, `07`, `31`, and `63`; they mix positive and negative V values across multiple K entries. The remaining lanes are explicit zero outputs.
- This is a deterministic scoreboard sentinel, not the final full random row golden. It uses the current exp exact-point constants and the bring-up reciprocal formula, so it must not be used as evidence that exp LUT/PWL or reciprocal v0.2 is frozen.

### `non_causal_smoke`

- `subset=q_index=00 first_tile only` in `meta.txt`.
- `score_tile.hex` and `mask_valid.hex` cover K positions `k=0..31` for `q=0`; all are valid because `causal=0`.
- `m_l_after_tile.hex` contains one line after tile `00`.
- `acc_after_tile.hex` contains 64 lines for tile `00`, one per output dimension.
- This subset is intended to align softmax state retention when a later valid score is equal to the current running max. In the generated case, `k=1` raises `m` to zero and `k=2` has `score == m`.
- For the equal-score update at `k=2`, the expected exact fields are:

```text
p       = 00800000
alpha   = 00800000
l_delta = 00800000
acc_delta[d] = V[2][d] << 23
m_new   = m_old
```

The `meta.txt` records first-valid state (`k=0`), the first equal-score state (`k=1`), and the second equal-score update (`k=2`). `acc_after_tile.hex` is a first-tile skeleton state. Its non-equal `k=0` contribution uses Python `math.exp` rounded to `U1.23` and is not a frozen LUT/rounding contract.

## Comparison Rules

- First compare `mask_valid`; mask errors usually corrupt all downstream state.
- Then compare `score_tile`; confirm whether values are raw dot or scaled score.
- Then compare `m_l_after_tile`.
- Then compare `acc_after_tile`.
- Then compare `recip_l`.
- Compare `O_q88` last.

Tolerance-based compare is acceptable for draft exp/recip implementations. Bit-exact compare should wait until fixed-point v1.0 freezes rounding, LUT tables, and reciprocal mode.

Exception: the manual `final_expected.txt` smoke files above are already bit-exact for their stated constants and rounding rule. Use them only for those narrow datapath checkpoints.
