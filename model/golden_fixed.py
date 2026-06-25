#!/usr/bin/env python3
"""Pure-Python integer oracle for the current RTL fixed-point behavior."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


EXP_FRAC_BITS = 23
EXP_ONE_U1_23 = 1 << EXP_FRAC_BITS
SCORE_FRAC_BITS = 16
SCORE_PIPE_BITS = 48
SOFTMAX_SCORE_BITS = 24
EXP_OUTPUT_BITS = 24
L_BITS = 32
ACC_BITS = 48
PWL_HALF_STEP_S16 = 1 << (SCORE_FRAC_BITS - 1)
PWL_TAIL_STEP_S16 = 12 << SCORE_FRAC_BITS
RECIP_NUMERATOR = (1 << 31) * (1 << 23)

# Current fa_exp_approx anchors from 0 through -4. The remaining interval is
# one RTL tail segment from (-4, 0x02582B) to (-16, 0).
_EXP_HALF_STEP_U1_23 = (
    0x800000, 0x4DA2CC, 0x2F16AC, 0x1C8F87,
    0x1152AB, 0x0A81C3, 0x065F6C, 0x03DD82,
    0x02582B,
)


@dataclass(frozen=True)
class FixedRowState:
    """Final integer state and output for one query row."""

    m_s32_16: int
    l_u9_23: int
    acc_s17_31: list[int]
    output_q88: list[int]


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
    """Match ``fa_exp_approx`` for a 24-bit signed S*.16 input."""

    x = wrap_signed(delta_s32_16, SOFTMAX_SCORE_BITS)
    if x >= 0:
        return EXP_ONE_U1_23
    if x <= -(16 << SCORE_FRAC_BITS):
        return 0

    magnitude = -x
    if magnitude <= (4 << SCORE_FRAC_BITS):
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

    return _interp_segment(
        x,
        -(4 << SCORE_FRAC_BITS),
        _EXP_HALF_STEP_U1_23[-1],
        0,
        PWL_TAIL_STEP_S16,
    )


def reciprocal_u1_31(l_u9_23: int) -> int:
    """Match the 32-bit reciprocal output container."""

    l_value = wrap_unsigned(l_u9_23, L_BITS)
    if l_value == 0:
        raise ValueError("l_u9_23 must be nonzero")
    reciprocal = (RECIP_NUMERATOR + l_value // 2) // l_value
    return wrap_unsigned(reciprocal, 32)


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
        elif score - m == (1 << SCORE_FRAC_BITS):
            alpha = _EXP_HALF_STEP_U1_23[2]
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
        # The current RTL has no generic higher-score path. Such inputs hold
        # state and deassert valid rather than updating m/l/acc.

    if m is None or l_value == 0:
        raise ValueError("row has no valid keys")

    reciprocal = reciprocal_u1_31(l_value)
    output = [finalize_q88(acc_value, reciprocal) for acc_value in acc]
    return FixedRowState(m, l_value, acc, output)


def attention_fixed(
    q_rows: Sequence[Sequence[int]],
    k_rows: Sequence[Sequence[int]],
    v_rows: Sequence[Sequence[int]],
    causal: bool = True,
    max_rows: int | None = None,
) -> list[list[int]]:
    """Compute fixed-point attention outputs for a prefix of query rows."""

    if len(q_rows) != len(k_rows) or len(k_rows) != len(v_rows):
        raise ValueError("Q, K, and V must have the same row count")
    row_count = len(q_rows) if max_rows is None else min(len(q_rows), max_rows)
    return [
        softmax_row_fixed(q_rows[row], k_rows, v_rows, row, causal).output_q88
        for row in range(row_count)
    ]
