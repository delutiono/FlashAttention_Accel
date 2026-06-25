#!/usr/bin/env python3
"""Bit-accurate division-free U9.23 reciprocal normalization and NR oracle."""

from __future__ import annotations

from dataclasses import dataclass


U32_MAX = (1 << 32) - 1
Q31_ONE = 1 << 31
Q31_TWO = 1 << 32
SUPPORTED_LUT_ENTRIES = (8, 16, 32, 64)
SUPPORTED_NR_ITERATIONS = (1, 2)

# Rounded reciprocal of each normalized-mantissa interval midpoint.
# These constants are generated offline and are ROM contents, not runtime math.
SEED_LUTS = {
    8: (
        0x78787878, 0x6BCA1AF3, 0x61861862, 0x590B2164,
        0x51EB851F, 0x4BDA12F7, 0x469EE584, 0x42108421,
    ),
    16: (
        0x7C1F07C2, 0x75075075, 0x6EB3E453, 0x69069069,
        0x63E7063E, 0x5F417D06, 0x5B05B05B, 0x572620AE,
        0x5397829D, 0x50505050, 0x4D4873ED, 0x4A7904A8,
        0x47DC11F7, 0x456C797E, 0x4325C53F, 0x41041041,
    ),
    32: (
        0x7E07E07E, 0x7A44C6B0, 0x76B981DB, 0x73615A24,
        0x70381C0E, 0x6D3A06D4, 0x6A63BD82, 0x67B23A54,
        0x6522C3F3, 0x62B2E43E, 0x60606060, 0x5E293206,
        0x5C0B8170, 0x5A05A05A, 0x58160581, 0x563B48C2,
        0x54741FAC, 0x52BF5A81, 0x511BE196, 0x4F88B2F4,
        0x4E04E04E, 0x4C8F8D29, 0x4B27ED36, 0x49CD42E2,
        0x487EDE05, 0x473C1AB7, 0x46046046, 0x44D72045,
        0x43B3D5B0, 0x429A042A, 0x4189374C, 0x40810204,
    ),
    64: (
        0x7F01FC08, 0x7D119679, 0x7B301ECC, 0x795CEB24,
        0x77975B90, 0x75DED953, 0x7432D63E, 0x7292CC15,
        0x70FE3C07, 0x6F74AE26, 0x6DF5B0F7, 0x6C80D902,
        0x6B15C06B, 0x69B4069B, 0x685B4FE6, 0x670B453C,
        0x65C393E0, 0x6483ED27, 0x634C0635, 0x621B97C3,
        0x60F25DEB, 0x5FD017F4, 0x5EB48824, 0x5D9F7391,
        0x5C90A1FD, 0x5B87DDAD, 0x5A84F345, 0x5987B1A9,
        0x588FE9DC, 0x579D6EE3, 0x56B015AC, 0x55C7B4F1,
        0x54E42524, 0x54054054, 0x532AE21D, 0x5254E78F,
        0x51832F20, 0x50B59897, 0x4FEC04FF, 0x4F265692,
        0x4E6470B0, 0x4DA637CF, 0x4CEB916D, 0x4C346405,
        0x4B809701, 0x4AD012B4, 0x4A22C04A, 0x497889C2,
        0x48D159E2, 0x482D1C32, 0x478BBCED, 0x46ED2901,
        0x46514E02, 0x45B81A25, 0x45217C38, 0x448D639D,
        0x43FBC044, 0x436C82A2, 0x42DF9BB1, 0x4254FCE4,
        0x41CC9829, 0x41465FDF, 0x40C246D4, 0x40404040,
    ),
}


@dataclass(frozen=True)
class NormalizedU9_23:
    """Normalized mantissa and base-two exponent for an unsigned input."""

    mantissa_u1_31: int
    exponent: int


@dataclass(frozen=True)
class ReciprocalNrTrace:
    """Observable checkpoints needed for Python and RTL bit matching."""

    normalized: NormalizedU9_23
    seed_index: int
    seed_u1_31: int
    iterates_u1_31: tuple[int, ...]
    reciprocal_u1_31: int
    divide_by_zero: bool
    valid_latency: int


def _validate_config(lut_entries: int, nr_iterations: int) -> None:
    if lut_entries not in SUPPORTED_LUT_ENTRIES:
        raise ValueError("lut_entries must be one of 8, 16, 32, or 64")
    if nr_iterations not in SUPPORTED_NR_ITERATIONS:
        raise ValueError("nr_iterations must be 1 or 2")


def valid_latency_cycles(nr_iterations: int) -> int:
    """Return accepted-input to output-valid latency for the frozen pipeline."""

    if nr_iterations not in SUPPORTED_NR_ITERATIONS:
        raise ValueError("nr_iterations must be 1 or 2")
    return 2 + (nr_iterations << 1)


def normalize_u9_23(value_u9_23: int) -> NormalizedU9_23:
    """Normalize nonzero U9.23 to U1.31 in [1, 2) plus a signed exponent."""

    value = value_u9_23 & U32_MAX
    if value == 0:
        return NormalizedU9_23(0, 0)
    msb_index = value.bit_length() - 1
    mantissa = (value << (31 - msb_index)) & U32_MAX
    return NormalizedU9_23(mantissa, msb_index - 23)


def seed_index_u1_31(mantissa_u1_31: int, lut_entries: int) -> int:
    """Select a seed using the top fractional bits of a normalized mantissa."""

    if lut_entries not in SUPPORTED_LUT_ENTRIES:
        raise ValueError("lut_entries must be one of 8, 16, 32, or 64")
    mantissa = mantissa_u1_31 & U32_MAX
    if mantissa < Q31_ONE:
        raise ValueError("mantissa must be normalized U1.31 in [1, 2)")
    index_bits = lut_entries.bit_length() - 1
    return (mantissa & (Q31_ONE - 1)) >> (31 - index_bits)


def _nr_step_trunc_u1_31(mantissa_u1_31: int, estimate_u1_31: int) -> int:
    product_q2_31 = (mantissa_u1_31 * estimate_u1_31) >> 31
    correction_q2_31 = Q31_TWO - product_q2_31
    refined = (estimate_u1_31 * correction_q2_31) >> 31
    return min(U32_MAX, max(0, refined))


def _denormalize_u1_31(estimate_u1_31: int, exponent: int) -> int:
    if exponent >= 0:
        return estimate_u1_31 >> exponent
    widened = estimate_u1_31 << (-exponent)
    return min(U32_MAX, widened)


def reciprocal_nr_trace(
    value_u9_23: int,
    *,
    lut_entries: int = 32,
    nr_iterations: int = 1,
) -> ReciprocalNrTrace:
    """Return all fixed-point checkpoints for one reciprocal transaction."""

    _validate_config(lut_entries, nr_iterations)
    normalized = normalize_u9_23(value_u9_23)
    latency = valid_latency_cycles(nr_iterations)
    if normalized.mantissa_u1_31 == 0:
        return ReciprocalNrTrace(
            normalized=normalized,
            seed_index=0,
            seed_u1_31=0,
            iterates_u1_31=(),
            reciprocal_u1_31=0,
            divide_by_zero=True,
            valid_latency=latency,
        )

    index = seed_index_u1_31(normalized.mantissa_u1_31, lut_entries)
    seed = SEED_LUTS[lut_entries][index]
    estimate = seed
    iterates = []
    for _ in range(nr_iterations):
        estimate = _nr_step_trunc_u1_31(
            normalized.mantissa_u1_31,
            estimate,
        )
        iterates.append(estimate)
    reciprocal = _denormalize_u1_31(estimate, normalized.exponent)
    return ReciprocalNrTrace(
        normalized=normalized,
        seed_index=index,
        seed_u1_31=seed,
        iterates_u1_31=tuple(iterates),
        reciprocal_u1_31=reciprocal,
        divide_by_zero=False,
        valid_latency=latency,
    )


def reciprocal_nr_u1_31(
    value_u9_23: int,
    *,
    lut_entries: int = 32,
    nr_iterations: int = 1,
) -> int:
    """Compute the frozen division-free reciprocal output."""

    return reciprocal_nr_trace(
        value_u9_23,
        lut_entries=lut_entries,
        nr_iterations=nr_iterations,
    ).reciprocal_u1_31
