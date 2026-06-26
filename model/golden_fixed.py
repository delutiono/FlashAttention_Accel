#!/usr/bin/env python3
"""Pure-Python integer oracle for the current RTL fixed-point behavior."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from model.recip_nr import reciprocal_nr_trace


EXP_FRAC_BITS = 23
EXP_ONE_U1_23 = 1 << EXP_FRAC_BITS
SCORE_FRAC_BITS = 16
SCORE_PIPE_BITS = 48
SOFTMAX_SCORE_BITS = 24
EXP_OUTPUT_BITS = 24
L_BITS = 32
ACC_BITS = 48
PWL_HALF_STEP_S16 = 1 << (SCORE_FRAC_BITS - 1)
RECIP_NUMERATOR = (1 << 31) * (1 << 23)
RECIP_MODE_EXACT = "exact"
RECIP_MODE_NR = "nr"
DEFAULT_RECIP_MODE = RECIP_MODE_NR
DEFAULT_RECIP_LUT_ENTRIES = 32
DEFAULT_RECIP_NR_ITERATIONS = 1

# Rounded exp(x) * 2^23 anchors for x = 0, -0.5, ..., -16.0.
_EXP_HALF_STEP_U1_23 = (
    0x800000, 0x4DA2CC, 0x2F16AC, 0x1C8F87,
    0x1152AB, 0x0A81C3, 0x065F6C, 0x03DD82,
    0x02582B, 0x016C05, 0x00DCCA, 0x0085EA,
    0x005139, 0x003144, 0x001DE1, 0x001220,
    0x000AFE, 0x0006AB, 0x00040B, 0x000274,
    0x00017D, 0x0000E7, 0x00008C, 0x000055,
    0x000034, 0x00001F, 0x000013, 0x00000C,
    0x000007, 0x000004, 0x000003, 0x000002,
    0x000001,
)


@dataclass(frozen=True)
class FixedRowState:
    """Final integer state and output for one query row."""

    m_s32_16: int
    l_u9_23: int
    acc_s17_31: list[int]
    output_q88: list[int]
    reciprocal_u1_31: int
    recip_mode: str
    recip_lut_entries: int
    recip_nr_iterations: int
    recip_valid_latency: int


def wrap_unsigned(value: int, bits: int) -> int:
    """Truncate to the low ``bits`` as an unsigned RTL container."""

    if bits <= 0:
        raise ValueError("bits must be positive")
    return value & ((1 << bits) - 1)


def wrap_signed(value: int, bits: int) -> int:
    """Truncate to the low ``bits`` and interpret them as two's-complement."""

    unsigned = wrap_unsigned(value, bits)
    sign_bit = 1 << (bits - 1)
    return unsigned - (1 << bits) if unsigned & sign_bit else unsigned


def round_half_away_div(numerator: int, denominator: int) -> int:
    """Round an integer ratio to nearest, with exact halves away from zero."""

    if denominator <= 0:
        raise ValueError("denominator must be positive")
    magnitude = abs(numerator)
    rounded = (magnitude + denominator // 2) // denominator
    return rounded if numerator >= 0 else -rounded


def saturate_int16(value: int) -> int:
    """Clamp an integer to the signed Q8.8 storage range."""

    return max(-32768, min(32767, value))


def scaled_score_s32_16(q_row: Sequence[int], k_row: Sequence[int]) -> int:
    """Match the 48-bit dot accumulator and signed arithmetic scale shift."""

    if len(q_row) != len(k_row):
        raise ValueError("Q and K row dimensions must match")
    raw_dot = 0
    for q_value, k_value in zip(q_row, k_row):
        product = wrap_signed(q_value, 16) * wrap_signed(k_value, 16)
        raw_dot = wrap_signed(raw_dot + wrap_signed(product, 32), SCORE_PIPE_BITS)
    return wrap_signed(raw_dot >> 3, SCORE_PIPE_BITS)


def _interp_segment(x: int, x_hi: int, y_hi: int, y_lo: int, step: int) -> int:
    offset = wrap_unsigned(x_hi - x, 32)
    difference = wrap_unsigned(y_hi - y_lo, 48)
    drop = (difference * wrap_unsigned(offset, 48) + (step >> 1)) // step
    return wrap_unsigned(y_hi - drop, EXP_OUTPUT_BITS)


def exp_pwl_u1_23(delta_s32_16: int) -> int:
    """Evaluate the 33-anchor PWL contract for a mathematical S*.16 delta."""

    x = delta_s32_16
    if x >= 0:
        return EXP_ONE_U1_23
    if x < -(16 << SCORE_FRAC_BITS):
        return 0

    magnitude = -x
    segment, remainder = divmod(magnitude, PWL_HALF_STEP_S16)
    if remainder == 0:
        return _EXP_HALF_STEP_U1_23[segment]
    x_hi = -(segment * PWL_HALF_STEP_S16)
    return _interp_segment(
        x,
        x_hi,
        _EXP_HALF_STEP_U1_23[segment],
        _EXP_HALF_STEP_U1_23[segment + 1],
        PWL_HALF_STEP_S16,
    )


def reciprocal_u1_31(l_u9_23: int) -> int:
    """Match the 32-bit reciprocal output container."""

    l_value = wrap_unsigned(l_u9_23, L_BITS)
    if l_value == 0:
        raise ValueError("l_u9_23 must be nonzero")
    reciprocal = (RECIP_NUMERATOR + l_value // 2) // l_value
    return wrap_unsigned(reciprocal, 32)


def reciprocal_for_finalize(
    l_u9_23: int,
    *,
    recip_mode: str = DEFAULT_RECIP_MODE,
    recip_lut_entries: int = DEFAULT_RECIP_LUT_ENTRIES,
    recip_nr_iterations: int = DEFAULT_RECIP_NR_ITERATIONS,
) -> tuple[int, int, int, int]:
    """Resolve reciprocal value plus LUT, iteration, and latency metadata."""

    if recip_mode == RECIP_MODE_EXACT:
        return reciprocal_u1_31(l_u9_23), 0, 0, 0
    if recip_mode != RECIP_MODE_NR:
        raise ValueError("recip_mode must be 'nr' or 'exact'")
    trace = reciprocal_nr_trace(
        l_u9_23,
        lut_entries=recip_lut_entries,
        nr_iterations=recip_nr_iterations,
    )
    if trace.divide_by_zero:
        raise ValueError("l_u9_23 must be nonzero")
    return (
        trace.reciprocal_u1_31,
        recip_lut_entries,
        recip_nr_iterations,
        trace.valid_latency,
    )


def finalize_q88(acc_s17_31: int, recip_u1_31: int) -> int:
    """Match the wrapped RTL inputs, half-away rounding, and saturation."""

    acc_value = wrap_signed(acc_s17_31, ACC_BITS)
    reciprocal = wrap_unsigned(recip_u1_31, 32)
    raw_q88 = round_half_away_div(acc_value * reciprocal, 1 << 54)
    return saturate_int16(raw_q88)


def softmax_row_fixed(
    q_row: Sequence[int],
    k_rows: Sequence[Sequence[int]],
    v_rows: Sequence[Sequence[int]],
    row_index: int,
    causal: bool = True,
    recip_mode: str = DEFAULT_RECIP_MODE,
    recip_lut_entries: int = DEFAULT_RECIP_LUT_ENTRIES,
    recip_nr_iterations: int = DEFAULT_RECIP_NR_ITERATIONS,
) -> FixedRowState:
    """Run scalar online softmax and all V lanes for one query row."""

    if len(k_rows) != len(v_rows):
        raise ValueError("K and V must have the same row count")
    if not k_rows:
        raise ValueError("at least one K/V row is required")
    if row_index < 0 or row_index >= len(k_rows):
        raise ValueError("row_index is outside the sequence")

    lane_count = len(v_rows[0])
    if any(len(v_row) != lane_count for v_row in v_rows):
        raise ValueError("all V rows must have the same lane count")

    m: int | None = None
    l_value = 0
    acc = [0] * lane_count

    for key_index, (k_row, v_row) in enumerate(zip(k_rows, v_rows)):
        if causal and key_index > row_index:
            continue

        score = wrap_signed(
            scaled_score_s32_16(q_row, k_row),
            SOFTMAX_SCORE_BITS,
        )
        v_values = [wrap_signed(value, 16) for value in v_row]
        if m is None:
            m = score
            l_value = wrap_unsigned(EXP_ONE_U1_23, L_BITS)
            acc = [
                wrap_signed(v_value << EXP_FRAC_BITS, ACC_BITS)
                for v_value in v_values
            ]
            continue

        if score == m:
            l_value = wrap_unsigned(l_value + EXP_ONE_U1_23, L_BITS)
            acc = [
                wrap_signed(acc_value + (v_value << EXP_FRAC_BITS), ACC_BITS)
                for acc_value, v_value in zip(acc, v_values)
            ]
        elif score < m:
            p_value = exp_pwl_u1_23(score - m)
            l_value = wrap_unsigned(l_value + p_value, L_BITS)
            acc = [
                wrap_signed(acc_value + (v_value * p_value), ACC_BITS)
                for acc_value, v_value in zip(acc, v_values)
            ]
        else:
            alpha = exp_pwl_u1_23(m - score)
            l_value = wrap_unsigned(
                ((l_value * alpha) >> EXP_FRAC_BITS) + EXP_ONE_U1_23,
                L_BITS,
            )
            acc = [
                wrap_signed(
                    wrap_signed((acc_value * alpha) >> EXP_FRAC_BITS, ACC_BITS)
                    + (v_value << EXP_FRAC_BITS),
                    ACC_BITS,
                )
                for acc_value, v_value in zip(acc, v_values)
            ]
            m = score

    if m is None or l_value == 0:
        raise ValueError("row has no valid keys")

    reciprocal, lut_entries, nr_iterations, valid_latency = reciprocal_for_finalize(
        l_value,
        recip_mode=recip_mode,
        recip_lut_entries=recip_lut_entries,
        recip_nr_iterations=recip_nr_iterations,
    )
    output = [finalize_q88(acc_value, reciprocal) for acc_value in acc]
    return FixedRowState(
        m,
        l_value,
        acc,
        output,
        reciprocal,
        recip_mode,
        lut_entries,
        nr_iterations,
        valid_latency,
    )


def attention_fixed(
    q_rows: Sequence[Sequence[int]],
    k_rows: Sequence[Sequence[int]],
    v_rows: Sequence[Sequence[int]],
    causal: bool = True,
    max_rows: int | None = None,
    recip_mode: str = DEFAULT_RECIP_MODE,
    recip_lut_entries: int = DEFAULT_RECIP_LUT_ENTRIES,
    recip_nr_iterations: int = DEFAULT_RECIP_NR_ITERATIONS,
) -> list[list[int]]:
    """Compute fixed-point attention outputs for a prefix of query rows."""

    if len(q_rows) != len(k_rows) or len(k_rows) != len(v_rows):
        raise ValueError("Q, K, and V must have the same row count")
    row_count = len(q_rows) if max_rows is None else min(len(q_rows), max_rows)
    return [
        softmax_row_fixed(
            q_rows[row],
            k_rows,
            v_rows,
            row,
            causal,
            recip_mode,
            recip_lut_entries,
            recip_nr_iterations,
        ).output_q88
        for row in range(row_count)
    ]
