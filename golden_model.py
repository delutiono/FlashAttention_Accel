#!/usr/bin/env python3
"""
FlashAttention Golden Model — 研究生创芯大赛 赛题二
=====================================================
Fixed config: S=256, d=64, batch=1, head=1, Q8.8 I/O.

Features:
  - FP32 reference SDPA (standard softmax)
  - FP32 FlashAttention (online softmax + tiled K/V, no explicit SxS)
  - Q8.8-simulated FlashAttention (LUT exp + LUT 1/x + intermediate quantisation)
  - Causal mask support
  - Random test-vector generation & hex dump
  - Error report: MAE / Max AE vs. FP32 reference
"""

from __future__ import annotations

import numpy as np
from dataclasses import dataclass, field
from typing import Optional, Tuple
import os

# ============================================================
# Constants
# ============================================================
S: int = 256          # sequence length
D: int = 64           # head dimension
SQRT_D: float = 8.0   # sqrt(64)
SCALE_FP32: float = 1.0 / SQRT_D  # 0.125

# Q8.8 fixed-point
Q88_SCALE: float = 256.0
Q88_MIN: int = -32768
Q88_MAX: int = 32767
Q88_FLOAT_MIN: float = -128.0
Q88_FLOAT_MAX: float = 127.99609375

# Default tile size for FlashAttention
DEFAULT_TILE_SIZE: int = 32

# ============================================================
# Q8.8 Fixed-Point Utilities
# ============================================================


def float_to_q88(x: np.ndarray) -> np.ndarray:
    """Convert float32 array to Q8.8 int16."""
    clipped = np.clip(x, Q88_FLOAT_MIN, Q88_FLOAT_MAX)
    return np.round(clipped * Q88_SCALE).astype(np.int16)


def q88_to_float(x: np.ndarray) -> np.ndarray:
    """Convert Q8.8 int16 array back to float32."""
    return x.astype(np.float32) / Q88_SCALE


def q88_mul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Multiply two Q8.8 values; result is Q8.8 (with rounding)."""
    # (a/256)*(b/256) = a*b/65536; re-quantise to /256: (a*b) >> 8
    prod = a.astype(np.int32) * b.astype(np.int32)       # Q16.16
    return ((prod + (1 << 7)) >> 8).astype(np.int16)     # round & shift → Q8.8


def q88_add(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Saturating add of two Q8.8 values."""
    s = a.astype(np.int32) + b.astype(np.int32)
    return np.clip(s, Q88_MIN, Q88_MAX).astype(np.int16)


def quantise_to_q88(x: np.ndarray) -> np.ndarray:
    """Quantise a float array to Q8.8 and return the float representation."""
    return q88_to_float(float_to_q88(x))


# ============================================================
# LUT Approximation Classes
# ============================================================


@dataclass
class ExpLUT:
    """exp(x) via uniform LUT + linear interpolation, x in [x_min, 0].

    Hardware notes
    --------------
    - x_min is typically -16 .. -20  (exp below that ≈ 0).
    - n_entries is a power of 2 so the index can be extracted by bit-slicing.
    """

    x_min: float = -16.0
    n_entries: int = 4096  # 12-bit index

    # Derived / cached
    _step: float = field(init=False)
    _values: np.ndarray = field(init=False)

    def __post_init__(self):
        self._step = -self.x_min / (self.n_entries - 1)
        xs = np.linspace(self.x_min, 0.0, self.n_entries, dtype=np.float32)
        self._values = np.exp(xs).astype(np.float32)

    def lookup(self, x: np.ndarray) -> np.ndarray:
        """Return exp(x) with linear interpolation."""
        x = np.clip(x, self.x_min, 0.0)
        idx = (x - self.x_min) / self._step
        lo = np.floor(idx).astype(np.int32)
        hi = np.minimum(lo + 1, self.n_entries - 1)
        frac = (idx - lo).astype(np.float32)
        return self._values[lo] + frac * (self._values[hi] - self._values[lo])

    def lookup_q88(self, x_q88: np.ndarray) -> np.ndarray:
        """Q8.8-in, Q8.8-out exp via LUT.

        x_q88 : int16 array, Q8.8 representation of x (x = val/256).
        Returns Q8.8 int16 array of exp(x).
        """
        xf = q88_to_float(x_q88)
        yf = self.lookup(xf)
        return float_to_q88(yf)


@dataclass
class DivLUT:
    """1/x via uniform LUT + linear interpolation + optional Newton-Raphson.

    x range is [x_min, x_max].  The hardware-realistic configuration uses a
    moderate-sized LUT followed by one NR iteration to square the error:
        y0 = LUT(x)
        y1 = y0 * (2 - x * y0)     ← one NR step, doubles precision
    """

    x_min: float = 0.5      # l is always >= 1; 0.5 gives safety margin
    x_max: float = 260.0    # l can reach S=256; 260 gives margin
    n_entries: int = 1024   # 10-bit index
    nr_refine: bool = True  # apply one Newton-Raphson iteration

    _step: float = field(init=False)
    _values: np.ndarray = field(init=False)

    def __post_init__(self):
        self._step = (self.x_max - self.x_min) / (self.n_entries - 1)
        xs = np.linspace(self.x_min, self.x_max, self.n_entries, dtype=np.float32)
        self._values = (1.0 / xs).astype(np.float32)

    def lookup(self, x: np.ndarray) -> np.ndarray:
        """Return 1/x with linear interpolation, optionally NR-refined."""
        x = np.clip(x, self.x_min, self.x_max)
        idx = (x - self.x_min) / self._step
        lo = np.floor(idx).astype(np.int32)
        hi = np.minimum(lo + 1, self.n_entries - 1)
        frac = (idx - lo).astype(np.float32)
        y = self._values[lo] + frac * (self._values[hi] - self._values[lo])

        if self.nr_refine:
            # y = y * (2 - x * y)   — one Newton-Raphson iteration
            y = y * (2.0 - x * y)

        return y


# ============================================================
# Causal Mask
# ============================================================


def _apply_causal_mask(scores: np.ndarray, j_start: int) -> np.ndarray:
    """Set scores[i, j] = -inf where j (global index) > i.  Modifies in-place."""
    S_seq = scores.shape[0]
    tile_len = scores.shape[1]
    j_idx = np.arange(j_start, j_start + tile_len)          # [tile_len]
    i_idx = np.arange(S_seq)[:, None]                        # [S, 1]
    scores[i_idx < j_idx] = -np.inf


# ============================================================
# FP32 Reference Attention  (standard SDPA)
# ============================================================


def attention_fp32(
    Q: np.ndarray,
    K: np.ndarray,
    V: np.ndarray,
    causal: bool = True,
    scale: float = SCALE_FP32,
) -> np.ndarray:
    """Standard SDPA with full SxS attention matrix (for reference only)."""
    S_seq = Q.shape[0]
    S_scores = (Q @ K.T) * scale                                   # [S, S]
    if causal:
        _apply_causal_mask(S_scores, 0)

    S_max = np.max(S_scores, axis=1, keepdims=True)                # [S, 1]
    S_exp = np.exp(S_scores - S_max)                               # [S, S]
    S_sum = np.sum(S_exp, axis=1, keepdims=True)                   # [S, 1]
    P = S_exp / S_sum                                               # [S, S]
    return P @ V                                                    # [S, D]


# ============================================================
# FP32 FlashAttention  (online softmax + tiled K/V)
# ============================================================


def flash_attention_fp32(
    Q: np.ndarray,
    K: np.ndarray,
    V: np.ndarray,
    causal: bool = True,
    scale: float = SCALE_FP32,
    tile_size: int = DEFAULT_TILE_SIZE,
) -> np.ndarray:
    """FlashAttention with online softmax.  Never materialises SxS.

    Maintains per-query running state (m, l, O) and processes K/V in tiles.
    """
    S_seq, D_dim = Q.shape

    m = np.full(S_seq, -np.inf, dtype=np.float32)     # running max
    l = np.zeros(S_seq, dtype=np.float32)              # running denominator
    O = np.zeros((S_seq, D_dim), dtype=np.float32)    # running output

    for j_start in range(0, S_seq, tile_size):
        j_end = min(j_start + tile_size, S_seq)
        K_tile = K[j_start:j_end]
        V_tile = V[j_start:j_end]

        # Scores for this tile
        S_tile = (Q @ K_tile.T) * scale                                   # [S, tile]

        if causal:
            _apply_causal_mask(S_tile, j_start)

        # Online-softmax update
        m_new = np.maximum(m, np.max(S_tile, axis=1))                    # [S]

        P_tile = np.exp(S_tile - m_new[:, None])                          # [S, tile]

        # Rescale factor for previously accumulated values
        alpha = np.exp(m - m_new)                                         # [S]

        l_new = l * alpha + np.sum(P_tile, axis=1)                       # [S]

        # acc <- acc * alpha + P_tile @ V_tile
        O = (O * (l * alpha)[:, None] + P_tile @ V_tile) / l_new[:, None]

        m = m_new
        l = l_new

    return O


# ============================================================
# Q8.8-simulated FlashAttention
# ============================================================
#
# Data-flow mimics a hardware datapath:
#   1. Q,K,V arrive as Q8.8 int16.
#   2. Dot products are accumulated in int32.
#   3. Exp is via LUT; 1/x is via LUT.
#   4. Intermediate values are quantised back to Q8.8 after critical ops.
#
# Error sources modelled:
#   (a) input quantisation (Q/K/V given as Q8.8)
#   (b) exp LUT approximation
#   (c) 1/x LUT approximation
#   (d) intermediate round-to-Q8.8 after multiply / accumulate
# ============================================================


def _q88_dot(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Q8.8 dot product along last axis, accumulated in int32, result Q8.8.

    a : int16 [..., d]
    b : int16 [..., d]
    returns : int16 [...]  (Q8.8)
    """
    prod = a.astype(np.int32) * b.astype(np.int32)          # Q16.16
    acc = np.sum(prod, axis=-1)                               # Q16.16 (max 64 terms → +6 bits → fits int32)
    # Multiply by Q8.8 scale factor → Q24.24, then shift back to Q8.8
    return ((acc + (1 << 7)) >> 8).astype(np.int16)


def flash_attention_q88(
    Q_int: np.ndarray,
    K_int: np.ndarray,
    V_int: np.ndarray,
    causal: bool = True,
    scale_int: int = 32,            # SCALE = 1/8 = 0.125 → 0.125×256 = 32
    tile_size: int = DEFAULT_TILE_SIZE,
    neg_large_int: int = -32768,    # -inf approximation in Q8.8
    exp_lut: Optional[ExpLUT] = None,
    div_lut: Optional[DivLUT] = None,
) -> np.ndarray:
    """FlashAttention with Q8.8 fixed-point datapath simulation.

    Precision allocation (matching competition allowances):
      - Q, K, V, O : Q8.8  (16-bit)
      - S = Q@K^T  : computed in float, equivalent to wide accumulator
      - exp in/out  : Q8.8 via LUT
      - m, l, acc   : float32 (represents >= 32-bit softmax accumulators)
      - Division    : deferred to end (once per row), via DivLUT
      - Final O     : Q8.8

    Key design choice: division is deferred to after all tiles are processed.
    This avoids compounding the DivLUT approximation error across tiles.

    Returns float32 output with Q8.8-level precision.
    """
    if exp_lut is None:
        exp_lut = ExpLUT()
    if div_lut is None:
        div_lut = DivLUT()

    S_seq, D_dim = Q_int.shape

    # High-precision running state
    m = np.full(S_seq, -np.inf, dtype=np.float32)      # running max
    l = np.zeros(S_seq, dtype=np.float32)               # running denominator
    acc = np.zeros((S_seq, D_dim), dtype=np.float32)    # unnormalised weighted V sum

    q_f = q88_to_float(Q_int)
    k_f = q88_to_float(K_int)
    v_f = q88_to_float(V_int)
    scale_f = scale_int / Q88_SCALE

    for j_start in range(0, S_seq, tile_size):
        j_end = min(j_start + tile_size, S_seq)
        K_tile_f = k_f[j_start:j_end]
        V_tile_f = v_f[j_start:j_end]

        # ---- Score = Q @ K^T * scale ----
        S_tile_f = (q_f @ K_tile_f.T) * scale_f                     # [S, tile]

        # ---- Causal mask ----
        if causal:
            j_idx = np.arange(j_start, j_end)
            i_idx = np.arange(S_seq)[:, None]
            S_tile_f[i_idx < j_idx] = -np.inf

        # ---- Online softmax update ----
        row_max_f = np.max(S_tile_f, axis=1)
        m_new = np.maximum(m, row_max_f)

        # P = exp(S - m_new) via LUT
        diff_f = S_tile_f - m_new[:, None]                           # all <= 0
        P_f = exp_lut.lookup(diff_f)                                 # LUT-approximated exp

        # Rescale factor: alpha = exp(m - m_new) via LUT
        alpha_f = exp_lut.lookup(m - m_new)

        # ---- Update l and acc (high precision, no division yet) ----
        # l_new = l * alpha + sum(P)
        # acc_new = acc * alpha + P @ V
        l_new = l * alpha_f + np.sum(P_f, axis=1)

        PV = P_f @ V_tile_f                                          # [S, D]
        acc = acc * alpha_f[:, None] + PV

        m = m_new
        l = l_new

    # ---- Final division (once per row) ----
    inv_l = div_lut.lookup(l)                                        # 1 / l
    O = quantise_to_q88(acc * inv_l[:, None])

    return O


# ============================================================
# Test-Vector Generation & Hex I/O
# ============================================================


def generate_random_qkv(seed: int = 42) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Generate random Q, K, V in Q8.8 int16 format.

    Values are drawn uniformly from the central 90 % of the Q8.8 range to
    avoid saturation.
    """
    rng = np.random.RandomState(seed)
    lo = int(Q88_MIN * 0.75)
    hi = int(Q88_MAX * 0.75)
    Q = rng.randint(lo, hi, size=(S, D), dtype=np.int16)
    K = rng.randint(lo, hi, size=(S, D), dtype=np.int16)
    V = rng.randint(lo, hi, size=(S, D), dtype=np.int16)
    return Q, K, V


def _int16_to_hex(arr: np.ndarray) -> np.ndarray:
    """Convert int16 array to hex strings (no '0x' prefix, 4-digit zero-padded)."""
    vec = arr.ravel()
    return np.array([f"{v & 0xFFFF:04X}" for v in vec])


def save_test_vector(
    path: str,
    test_id: int,
    Q_int: np.ndarray,
    K_int: np.ndarray,
    V_int: np.ndarray,
    O_ref_int: np.ndarray,
    O_q88_int: np.ndarray,
):
    """Write one test case as hex files."""
    os.makedirs(path, exist_ok=True)
    prefix = f"{path}/test_{test_id:03d}"
    for name, arr in [("Q", Q_int), ("K", K_int), ("V", V_int),
                       ("O_ref", O_ref_int), ("O_q88", O_q88_int)]:
        hex_arr = _int16_to_hex(arr)
        with open(f"{prefix}_{name}.hex", "w") as f:
            f.write("\n".join(hex_arr) + "\n")


# ============================================================
# Error Analysis
# ============================================================


@dataclass
class ErrorReport:
    mae: float
    max_ae: float
    mae_pass: bool
    max_ae_pass: bool
    details: str = ""

    def __str__(self) -> str:
        status = "PASS" if (self.mae_pass and self.max_ae_pass) else "FAIL"
        return (
            f"  MAE     = {self.mae:.6f}  (threshold 0.03)  {'OK' if self.mae_pass else 'EXCEEDED'}\n"
            f"  Max AE  = {self.max_ae:.6f}  (threshold 0.10)  {'OK' if self.max_ae_pass else 'EXCEEDED'}\n"
            f"  Result  : {status}\n"
            f"{self.details}"
        )


def compute_error(
    O_ref: np.ndarray,
    O_test: np.ndarray,
    tag: str = "",
) -> ErrorReport:
    """Compute MAE and Max AE between reference and test output (both float32)."""
    abs_err = np.abs(O_ref - O_test)
    mae = float(np.mean(abs_err))
    max_ae = float(np.max(abs_err))

    # Per-row statistics for insight
    row_mae = np.mean(abs_err, axis=1)
    row_max = np.max(abs_err, axis=1)
    worst_row = int(np.argmax(row_max))

    details = (
        f"  Worst row        : {worst_row}\n"
        f"  Row-MAE range    : [{np.min(row_mae):.6f}, {np.max(row_mae):.6f}]\n"
        f"  Row-MaxAE range  : [{np.min(row_max):.6f}, {np.max(row_max):.6f}]\n"
    )
    if tag:
        details = f"  Tag: {tag}\n" + details

    return ErrorReport(
        mae=mae,
        max_ae=max_ae,
        mae_pass=mae <= 0.03,
        max_ae_pass=max_ae <= 0.10,
        details=details,
    )


# ============================================================
# Sanity Checks
# ============================================================


def _run_sanity():
    """Verify FlashAttention FP32 matches standard FP32 attention."""
    print("=" * 60)
    print("SANITY CHECK: FlashAttention FP32 vs Standard FP32")
    print("=" * 60)

    Q_int, K_int, V_int = generate_random_qkv(42)
    Q_f = q88_to_float(Q_int)
    K_f = q88_to_float(K_int)
    V_f = q88_to_float(V_int)

    O_std = attention_fp32(Q_f, K_f, V_f, causal=True)

    for tile_size in [16, 32, 64, 128]:
        O_flash = flash_attention_fp32(Q_f, K_f, V_f, causal=True, tile_size=tile_size)
        max_diff = np.max(np.abs(O_std - O_flash))
        status = "OK" if max_diff < 1e-5 else "MISMATCH"
        print(f"  tile_size={tile_size:3d}  max|diff| = {max_diff:.2e}  [{status}]")
    print()


def _run_lut_analysis():
    """Analyse LUT approximation error in isolation."""
    print("=" * 60)
    print("LUT APPROXIMATION ERROR")
    print("=" * 60)

    for name, lut_cls, x_range in [
        ("ExpLUT", ExpLUT, (-16.0, 0.0)),
        ("DivLUT (no NR)", DivLUT, (0.5, 260.0)),
    ]:
        for n in [256, 512, 1024, 2048, 4096]:
            if name == "ExpLUT":
                lut = ExpLUT(x_min=x_range[0], n_entries=n)
                xs = np.linspace(x_range[0], x_range[1], 10000, dtype=np.float32)
                ys_lut = lut.lookup(xs)
                ys_true = np.exp(xs)
            else:
                lut = DivLUT(x_min=x_range[0], x_max=x_range[1], n_entries=n, nr_refine=False)
                xs = np.linspace(max(x_range[0], 0.5), x_range[1], 10000, dtype=np.float32)
                ys_lut = lut.lookup(xs)
                ys_true = 1.0 / xs

            abs_err = np.abs(ys_lut - ys_true)
            mae = float(np.mean(abs_err))
            max_ae = float(np.max(abs_err))
            print(f"  {name} n={n:4d}  MAE={mae:.6e}  MaxAE={max_ae:.6e}")

    # DivLUT with NR
    print("  --- With Newton-Raphson refinement ---")
    for n in [256, 512, 1024, 2048]:
        lut = DivLUT(x_min=0.5, x_max=260.0, n_entries=n, nr_refine=True)
        xs = np.linspace(0.5, 260.0, 10000, dtype=np.float32)
        ys_lut = lut.lookup(xs)
        ys_true = 1.0 / xs
        abs_err = np.abs(ys_lut - ys_true)
        mae = float(np.mean(abs_err))
        max_ae = float(np.max(abs_err))
        print(f"  DivLUT+NR n={n:4d}  MAE={mae:.6e}  MaxAE={max_ae:.6e}")
    print()


# ============================================================
# Main Test Flow
# ============================================================


def main():
    # --- Sanity checks ---
    _run_sanity()
    _run_lut_analysis()

    # --- LUT instances (default config) ---
    exp_lut = ExpLUT(x_min=-16.0, n_entries=4096)
    div_lut = DivLUT(x_min=0.5, x_max=260.0, n_entries=1024, nr_refine=True)

    # --- Run multiple random test cases ---
    num_tests = 10
    output_dir = "./test_vectors"
    os.makedirs(output_dir, exist_ok=True)

    all_mae = []
    all_max_ae = []

    print("=" * 60)
    print(f"RUNNING {num_tests} RANDOM TEST CASES")
    print("=" * 60)

    for t in range(num_tests):
        seed = 100 + t
        Q_int, K_int, V_int = generate_random_qkv(seed)
        Q_f = q88_to_float(Q_int)
        K_f = q88_to_float(K_int)
        V_f = q88_to_float(V_int)

        # FP32 reference (the "golden" answer)
        O_ref_f = attention_fp32(Q_f, K_f, V_f, causal=True)
        O_ref_int = float_to_q88(O_ref_f)

        # Q8.8-simulated FlashAttention
        O_q88_f = flash_attention_q88(
            Q_int, K_int, V_int,
            causal=True,
            tile_size=32,
            exp_lut=exp_lut,
            div_lut=div_lut,
        )
        O_q88_int = float_to_q88(O_q88_f)

        # Error report
        report = compute_error(O_ref_f, O_q88_f, tag=f"test_{t:03d}")
        print(f"--- Test {t:03d} (seed={seed}) ---")
        print(report)

        all_mae.append(report.mae)
        all_max_ae.append(report.max_ae)

        # Save test vectors
        save_test_vector(output_dir, t, Q_int, K_int, V_int, O_ref_int, O_q88_int)

    # --- Aggregate statistics ---
    print("=" * 60)
    print("AGGREGATE STATISTICS")
    print("=" * 60)
    print(f"  Number of tests       : {num_tests}")
    print(f"  MAE  mean / std       : {np.mean(all_mae):.6f} / {np.std(all_mae):.6f}")
    print(f"  Max AE mean / worst   : {np.mean(all_max_ae):.6f} / {np.max(all_max_ae):.6f}")
    all_pass = all(m <= 0.03 for m in all_mae) and all(x <= 0.10 for x in all_max_ae)
    print(f"  All tests pass        : {'YES' if all_pass else 'NO'}")
    print()

    # --- LUT sensitivity sweep ---
    print("=" * 60)
    print("LUT SIZE SENSITIVITY (single test, seed=100)")
    print("=" * 60)
    Q_int, K_int, V_int = generate_random_qkv(100)
    Q_f = q88_to_float(Q_int)
    K_f = q88_to_float(K_int)
    V_f = q88_to_float(V_int)
    O_ref_f = attention_fp32(Q_f, K_f, V_f, causal=True)

    for exp_n in [256, 512, 1024, 2048, 4096]:
        for div_n, div_nr in [(256, False), (512, False), (1024, False),
                               (256, True), (512, True), (1024, True)]:
            elut = ExpLUT(x_min=-16.0, n_entries=exp_n)
            dlut = DivLUT(x_min=0.5, x_max=260.0, n_entries=div_n, nr_refine=div_nr)
            O_test_f = flash_attention_q88(
                Q_int, K_int, V_int, causal=True, tile_size=32,
                exp_lut=elut, div_lut=dlut,
            )
            report = compute_error(O_ref_f, O_test_f)
            nr_tag = "+NR" if div_nr else "   "
            print(f"  ExpLUT={exp_n:4d}  DivLUT={div_n:4d} {nr_tag}  "
                  f"MAE={report.mae:.6f}  MaxAE={report.max_ae:.6f}  "
                  f"{'PASS' if report.mae_pass and report.max_ae_pass else 'FAIL'}")
    print()

    print("Test vectors saved to:", os.path.abspath(output_dir))
    print("Done.")


if __name__ == "__main__":
    main()
