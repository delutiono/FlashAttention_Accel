#!/usr/bin/env python3
"""
RTL Behavioral Model — bit-accurate emulation of the hardware datapath.
Matches the fixed-point formats and pipeline behavior of each RTL module:

  fa_exp_approx    : 4096-entry LUT, Q8.8 in, Q0.16 out
  fa_recip_approx  : 1024-entry LUT + NR, Q16.16 in/out
  fa_dot_pe        : LANES=32, 48-bit acc, Q16.16
  fa_softmax_online: dual exp, V_ACC_LANES=16, Q16.32 acc
  fa_out_quant     : acc * inv_l >> 40, round, saturate Q8.8
  fa_scheduler     : BQ=1, BK=32, causal mask

This model is the reference for RTL verification.
"""

import numpy as np
from dataclasses import dataclass

# ============================================================
# Constants (matching fa_defines.vh)
# ============================================================
S, D = 256, 64
ELEM_W = 16
BK = 32
DOT_LANES = 32
V_LANES = 16

# Fixed-point formats
EXP_IN_W = 16       # Q8.8 signed
EXP_OUT_W = 16      # Q0.16 unsigned
RECIP_W = 32        # Q16.16 unsigned
SCORE_W = 24        # Q8.16 signed
L_W = 32            # Q16.16 unsigned
ACC_W = 48          # Q16.32 signed

Q88_SCALE = 256.0
Q88_MIN = -32768
Q88_MAX = 32767

# Most negative Q8.16 value for softmax m_init (not -32768 which is only -0.5)
NEG_LARGE_Q816 = -(1 << 23)  # -8388608

# ============================================================
# LUT Generation (matching RTL $readmemh files)
# ============================================================

@dataclass
class ExpLUT:
    """4096-entry exp LUT, Q0.16 output, [-16, 0] input range."""
    n_entries: int = 4096
    x_min: float = -16.0  # Q8.8: -4096
    out_bits: int = 16

    def __post_init__(self):
        xs = np.linspace(self.x_min, 0.0, self.n_entries, dtype=np.float64)
        ys = np.exp(xs)
        self.values = np.round(ys * (1 << self.out_bits)).astype(np.uint32)
        self.values = np.clip(self.values, 0, (1 << self.out_bits) - 1)

    def lookup(self, x_q88: np.ndarray) -> np.ndarray:
        """x_q88: signed int16 array (Q8.8), clamped to [-4096, 0].
        Returns unsigned uint16 array (Q0.16)."""
        x = np.clip(x_q88, -4096, 0).astype(np.int32)
        idx = (x + 4096).astype(np.int32)
        idx = np.clip(idx, 0, self.n_entries - 1)
        return self.values[idx]


@dataclass
class RecipLUT:
    """4096-entry 1/x LUT + Newton-Raphson. Q16.16 in/out."""
    n_entries: int = 4096
    x_min: float = 0.5     # Q16.16: 32768
    step: float = 0.0625    # Q16.16: 4096 (>> 12)
    out_bits: int = 32

    def __post_init__(self):
        xs = np.array([self.x_min + k * self.step for k in range(self.n_entries)],
                      dtype=np.float64)
        ys = 1.0 / xs
        self.values = np.round(ys * 65536.0).astype(np.uint64)
        self.values = np.clip(self.values, 0, 0xFFFFFFFF)

    def lookup(self, x_q16: np.ndarray) -> np.ndarray:
        """x_q16: unsigned uint32 (Q16.16). Returns uint32 (Q16.16)."""
        x = np.clip(x_q16.astype(np.uint64), 32768, 0xFFFFFFFF)
        idx = ((x - 32768) >> 12).astype(np.int32)
        idx = np.clip(idx, 0, self.n_entries - 1)
        y0 = self.values[idx].astype(np.uint64)

        # Newton-Raphson: y = y0 * (2 - x * y0)  in Q16.16
        prod = (x * y0) >> 16           # Q16.16
        diff = (2 << 16) - prod          # Q16.16 (unsigned underflow handled)
        y1 = (y0 * diff) >> 16           # Q16.16
        return y1.astype(np.uint32)


# ============================================================
# RTL-accurate compute functions
# ============================================================

def _trunc_s48(x):
    """Truncate Python int to signed 48-bit (matching RTL ACC_W=48)."""
    mask48 = (1 << 48) - 1
    x = int(x) & mask48
    if x & (1 << 47):
        x = x - (1 << 48)
    return x


def _trunc_s24(x):
    """Truncate Python int to signed 24-bit (matching RTL SCORE_W=24)."""
    mask24 = (1 << 24) - 1
    x = int(x) & mask24
    if x & (1 << 23):
        x = x - (1 << 24)
    return x


def rtl_dot_product(q_row: np.ndarray, k_row: np.ndarray) -> np.int64:
    """fa_dot_pe: 64-element Q8.8 dot product, 48-bit accumulator.
    q_row, k_row: int16 arrays of length 64.
    Returns: int64 (48-bit truncated) Q16.16."""
    total = 0
    for i in range(len(q_row)):
        prod = int(q_row[i]) * int(k_row[i])  # Q16.16
        total = _trunc_s48(total + prod)
    return np.int64(total)


def rtl_score_scale(dot: np.int64, scale_q88: int = 32) -> int:
    """Scale dot product to score (matching RTL 24-bit truncation).
    dot: Q16.16 (48-bit), scale_q88: Q8.8 (default 32 = 0.125).
    Returns: Python int Q8.16 (24-bit signed)."""
    prod = _trunc_s48(int(dot) * scale_q88)  # 48-bit multiply
    shifted = prod >> 8  # arithmetic shift (Python int preserves sign)
    return _trunc_s24(shifted)


def rtl_softmax_update(
    score_q816: np.ndarray,    # [n_scores] Q8.16 signed
    v_rows: np.ndarray,        # [n_scores, D] Q8.8 signed
    m_q816: np.ndarray,        # [n_scores] Q8.16, running max
    l_q16: np.ndarray,         # [n_scores] Q16.16 unsigned, running denominator
    acc_q1632: np.ndarray,     # [n_scores, D] Q16.32, running acc
    exp_lut: ExpLUT,
    causal_mask: np.ndarray,
) -> tuple:
    """
    fa_softmax_online RTL behavior:
    For each score:
      1. m_new = max(m, score)
      2. P = exp(score - m_new) via LUT
      3. alpha = exp(m - m_new) via LUT
      4. l_new = (l * alpha) >> 16 + P
      5. acc_new = (acc * alpha) >> 16 + P * V[j]
    """
    m_new = np.maximum(m_q816, np.where(causal_mask, score_q816, NEG_LARGE_Q816))
    score_diff = np.where(
        causal_mask & (score_q816 > m_q816),
        0,
        (score_q816 - m_q816) >> 8
    ).astype(np.int32)
    P_q016 = exp_lut.lookup(score_diff.astype(np.int16))

    m_diff = np.where(
        m_q816 == NEG_LARGE_Q816,
        0,
        (m_q816 - m_new) >> 8
    ).astype(np.int32)
    alpha_q016 = np.where(
        m_q816 == NEG_LARGE_Q816,
        0xFFFF,  # alpha = 1.0 when no previous state
        exp_lut.lookup(m_diff.astype(np.int16))
    ).astype(np.uint32)

    # l update — use float64 then // to avoid numpy right_shift ufunc type errors
    l_scaled = (l_q16.astype(np.float64) * alpha_q016.astype(np.float64)) // 65536.0
    l_new = (l_scaled + P_q016.astype(np.float64)).astype(np.uint64)

    # acc update: acc_new = (acc * alpha) >> 16 + P * V
    acc_scaled = (acc_q1632.astype(np.float64) * alpha_q016.astype(np.float64)[:, None]) // 65536.0
    PxV = (P_q016.astype(np.float64)[:, None] * v_rows.astype(np.float64)) * 256.0  # << 8, Q16.32
    acc_new = (acc_scaled + PxV).astype(np.int64)

    return m_new.astype(np.int32), l_new.astype(np.uint64), acc_new.astype(np.int64)


def rtl_finalize(acc_q1632: np.ndarray, l_q16: np.ndarray, recip_lut: RecipLUT) -> np.ndarray:
    """fa_out_quant: O = quantize(acc / l) to Q8.8.
    acc: [D] Q16.32 signed
    l: scalar Q16.16 unsigned
    Returns: [D] Q8.8 signed int16."""
    inv_l = recip_lut.lookup(np.array([l_q16], dtype=np.uint64))[0]
    o_q88 = np.zeros(D, dtype=np.int32)
    for d in range(D):
        prod = int(acc_q1632[d]) * int(inv_l)  # Q32.48, Python int for safe multiply
        rounded = prod + (1 << 39)
        val = rounded >> 40  # Q8.8
        if val > Q88_MAX:
            val = Q88_MAX
        elif val < Q88_MIN:
            val = Q88_MIN
        o_q88[d] = val
    return o_q88.astype(np.int16)


# ============================================================
# Full RTL-emulated FlashAttention
# ============================================================

def flash_attention_rtl(
    Q: np.ndarray,     # [S, D] Q8.8 int16
    K: np.ndarray,     # [S, D] Q8.8 int16
    V: np.ndarray,     # [S, D] Q8.8 int16
    causal: bool = True,
    scale_q88: int = 32,
    exp_lut: ExpLUT = None,
    recip_lut: RecipLUT = None,
) -> np.ndarray:
    """
    RTL-accurate FlashAttention emulation.
    Matches the hardware pipeline: BQ=1, BK=32, DOT_LANES=32, V_LANES=16.
    """
    if exp_lut is None:
        exp_lut = ExpLUT()
    if recip_lut is None:
        recip_lut = RecipLUT()

    O = np.zeros((S, D), dtype=np.int16)

    for q_row in range(S):
        q_vec = Q[q_row]  # [D] Q8.8

        m_q816 = np.int32(NEG_LARGE_Q816)  # Q8.16, most negative
        l_q16 = np.uint64(0)       # Q16.16
        acc_q1632 = np.zeros(D, dtype=np.int64)  # Q16.32

        for tile_start in range(0, S, BK):
            tile_end = min(tile_start + BK, S)
            tile_len = tile_end - tile_start

            K_tile = K[tile_start:tile_end]  # [tile_len, D]
            V_tile = V[tile_start:tile_end]  # [tile_len, D]

            for k_off in range(tile_len):
                k_global = tile_start + k_off

                # causal mask
                if causal and k_global > q_row:
                    continue

                k_vec = K_tile[k_off]
                v_vec = V_tile[k_off]

                # dot product
                dot_q16 = rtl_dot_product(q_vec, k_vec)  # Q16.16
                score_q816 = rtl_score_scale(dot_q16, scale_q88)  # Q8.16

                # online softmax update
                m_old = m_q816
                m_new = max(m_old, score_q816)

                # P = exp(score - m_new)
                diff = 0 if score_q816 > m_old else (score_q816 - m_new) >> 8
                P = exp_lut.lookup(np.array([diff], dtype=np.int16))[0]

                # alpha = exp(m - m_new)
                if m_old == NEG_LARGE_Q816:
                    alpha = 0xFFFF
                else:
                    alpha_diff = (m_old - m_new) >> 8
                    alpha = exp_lut.lookup(np.array([alpha_diff], dtype=np.int16))[0]

                # l update — convert to Python int to avoid numpy right_shift type errors
                l_scaled = (int(l_q16) * int(alpha)) >> 16
                l_q16 = np.uint64(l_scaled + int(P))

                # acc update — pure Python int to avoid float64 precision loss
                alpha_i = int(alpha)
                P_i = int(P)
                alpha_needed = (m_old != NEG_LARGE_Q816) and (score_q816 > m_old)
                for d in range(D):
                    if alpha_needed:
                        acc_q1632[d] = (int(acc_q1632[d]) * alpha_i) >> 16
                    acc_q1632[d] = acc_q1632[d] + (P_i * int(v_vec[d]) << 8)

                m_q816 = m_new

        # Finalize: O = acc / l
        O[q_row] = rtl_finalize(acc_q1632, l_q16, recip_lut)

    return O


# ============================================================
# Validation
# ============================================================

if __name__ == "__main__":
    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from golden_model import (
        float_to_q88, q88_to_float,
        attention_fp32, compute_error
    )

    print("=" * 60)
    print("RTL Behavioral Model Validation")
    print("=" * 60)

    exp_lut = ExpLUT()
    recip_lut = RecipLUT()

    num_tests = 10
    all_mae, all_max_ae = [], []

    for t in range(num_tests):
        seed = 100 + t
        rng = np.random.RandomState(seed)
        # Generate values within Q8.16-safe range: [-2.0, 2.0] float -> [-512, 512] Q8.8
        # This keeps dot products small enough that scores stay in 24-bit Q8.16 range
        q_f = rng.uniform(-2.0, 2.0, size=(S, D)).astype(np.float32)
        k_f = rng.uniform(-2.0, 2.0, size=(S, D)).astype(np.float32)
        v_f = rng.uniform(-2.0, 2.0, size=(S, D)).astype(np.float32)
        Q_int = float_to_q88(q_f)
        K_int = float_to_q88(k_f)
        V_int = float_to_q88(v_f)

        # Reference: FP32 SDPA
        O_ref_f = attention_fp32(q_f, k_f, v_f, causal=True)

        # RTL behavioral model
        O_rtl_int = flash_attention_rtl(Q_int, K_int, V_int, causal=True,
                                        exp_lut=exp_lut, recip_lut=recip_lut)
        O_rtl_f = q88_to_float(O_rtl_int)

        report = compute_error(O_ref_f, O_rtl_f, tag=f"rtl_test_{t:03d}")
        print(f"--- Test {t:03d} (seed={seed}) ---")
        print(report)

        all_mae.append(report.mae)
        all_max_ae.append(report.max_ae)

    print("=" * 60)
    print("AGGREGATE STATISTICS")
    print("=" * 60)
    print(f"  MAE  mean: {np.mean(all_mae):.6f}  worst: {np.max(all_mae):.6f}")
    print(f"  Max AE mean: {np.mean(all_max_ae):.6f}  worst: {np.max(all_max_ae):.6f}")
    all_pass = all(m <= 0.03 for m in all_mae) and all(x <= 0.10 for x in all_max_ae)
    print(f"  All tests pass: {'YES' if all_pass else 'NO'}")
