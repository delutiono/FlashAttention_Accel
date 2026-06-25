#!/usr/bin/env python3
"""Regress the current RTL integer oracle against an ideal softmax reference."""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path
from typing import Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from model.golden_fixed import attention_fixed, scaled_score_s32_16  # noqa: E402


def _random_matrix(rng: random.Random, rows: int, columns: int, low: int, high: int) -> list[list[int]]:
    return [[rng.randint(low, high) for _ in range(columns)] for _ in range(rows)]


def generate_qkv(seed: int, sequence_length: int, dimension: int) -> tuple[list[list[int]], ...]:
    """Generate controlled Q8.8 inputs that exercise softmax mixing."""

    rng = random.Random(seed)
    q_rows = _random_matrix(rng, sequence_length, dimension, -256, 256)
    k_rows = _random_matrix(rng, sequence_length, dimension, -256, 256)
    v_rows = _random_matrix(rng, sequence_length, dimension, -512, 512)
    return q_rows, k_rows, v_rows


def _half_away_float_to_q88(value: float) -> int:
    scaled = value * 256.0
    rounded = math.floor(abs(scaled) + 0.5)
    signed = rounded if scaled >= 0.0 else -rounded
    return max(-32768, min(32767, signed))


def ideal_attention_rows(
    q_rows: Sequence[Sequence[int]],
    k_rows: Sequence[Sequence[int]],
    v_rows: Sequence[Sequence[int]],
    max_rows: int | None,
) -> tuple[list[list[float]], list[list[int]]]:
    """Independent ideal-exp causal reference using the same raw >>> 3 score contract."""

    row_count = len(q_rows) if max_rows is None else min(len(q_rows), max_rows)
    float_output: list[list[float]] = []
    q88_output: list[list[int]] = []

    for row_index in range(row_count):
        scores = [
            scaled_score_s32_16(q_rows[row_index], k_rows[key_index]) / 65536.0
            for key_index in range(row_index + 1)
        ]
        row_max = max(scores)
        weights = [math.exp(score - row_max) for score in scores]
        denominator = sum(weights)
        output_row = [
            sum(
                weight * (v_rows[key_index][lane] / 256.0)
                for key_index, weight in enumerate(weights)
            ) / denominator
            for lane in range(len(v_rows[0]))
        ]
        float_output.append(output_row)
        q88_output.append([_half_away_float_to_q88(value) for value in output_row])

    return float_output, q88_output


def run_case(seed: int, sequence_length: int, dimension: int, max_rows: int | None) -> dict[str, int | float]:
    q_rows, k_rows, v_rows = generate_qkv(seed, sequence_length, dimension)
    fixed_q88 = attention_fixed(q_rows, k_rows, v_rows, causal=True, max_rows=max_rows)
    reference_float, reference_q88 = ideal_attention_rows(q_rows, k_rows, v_rows, max_rows)

    total_float_error = 0.0
    max_float_error = 0.0
    total_lsb_error = 0
    max_lsb_error = 0
    element_count = 0
    worst_row = 0

    for row_index, (fixed_row, ref_float_row, ref_q88_row) in enumerate(
        zip(fixed_q88, reference_float, reference_q88)
    ):
        row_max = 0.0
        for fixed_value, ref_float_value, ref_q88_value in zip(fixed_row, ref_float_row, ref_q88_row):
            float_error = abs((fixed_value / 256.0) - ref_float_value)
            lsb_error = abs(fixed_value - ref_q88_value)
            total_float_error += float_error
            total_lsb_error += lsb_error
            max_float_error = max(max_float_error, float_error)
            max_lsb_error = max(max_lsb_error, lsb_error)
            row_max = max(row_max, float_error)
            element_count += 1
        if row_max >= max_float_error:
            worst_row = row_index

    return {
        "seed": seed,
        "rows": len(fixed_q88),
        "elements": element_count,
        "mae": total_float_error / element_count,
        "max_ae": max_float_error,
        "mae_q88_lsb": total_lsb_error / element_count,
        "max_ae_q88_lsb": max_lsb_error,
        "worst_row": worst_row,
    }


def _parse_seeds(text: str) -> list[int]:
    seeds = [int(item.strip()) for item in text.split(",") if item.strip()]
    if not seeds:
        raise argparse.ArgumentTypeError("at least one seed is required")
    return seeds


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=_parse_seeds, default=_parse_seeds("100,101,102,103,104"))
    parser.add_argument("--sequence-length", type=int, default=256)
    parser.add_argument("--dimension", type=int, default=64)
    parser.add_argument(
        "--max-rows",
        type=int,
        default=None,
        help="Only evaluate this many query rows; default evaluates all rows.",
    )
    parser.add_argument("--require-mae", type=float, default=None, help="Require aggregate mean MAE at or below this value.")
    parser.add_argument(
        "--require-maxae",
        type=float,
        default=None,
        help="Require aggregate worst MaxAE at or below this value.",
    )
    parser.add_argument("--json", action="store_true", help="Emit one deterministic JSON object.")
    args = parser.parse_args()

    if args.sequence_length <= 0 or args.dimension <= 0:
        parser.error("sequence length and dimension must be positive")
    if args.max_rows is not None and args.max_rows <= 0:
        parser.error("--max-rows must be positive")
    if args.require_mae is not None and args.require_mae < 0:
        parser.error("--require-mae must be nonnegative")
    if args.require_maxae is not None and args.require_maxae < 0:
        parser.error("--require-maxae must be nonnegative")

    cases = [
        run_case(seed, args.sequence_length, args.dimension, args.max_rows)
        for seed in args.seeds
    ]
    aggregate = {
        "seeds": args.seeds,
        "sequence_length": args.sequence_length,
        "dimension": args.dimension,
        "max_rows": args.max_rows,
        "cases": cases,
        "mean_mae": sum(float(case["mae"]) for case in cases) / len(cases),
        "worst_max_ae": max(float(case["max_ae"]) for case in cases),
        "mean_mae_q88_lsb": sum(float(case["mae_q88_lsb"]) for case in cases) / len(cases),
        "worst_max_ae_q88_lsb": max(int(case["max_ae_q88_lsb"]) for case in cases),
    }
    failures = []
    for case in cases:
        if args.require_mae is not None and float(case["mae"]) > args.require_mae:
            failures.append(
                f"seed={case['seed']} MAE threshold exceeded: "
                f"MAE={case['mae']:.8f} > require_MAE={args.require_mae:.8f}"
            )
        if args.require_maxae is not None and float(case["max_ae"]) > args.require_maxae:
            failures.append(
                f"seed={case['seed']} MaxAE threshold exceeded: "
                f"MaxAE={case['max_ae']:.8f} > require_MaxAE={args.require_maxae:.8f}"
            )
    aggregate["require_mae"] = args.require_mae
    aggregate["require_maxae"] = args.require_maxae
    aggregate["threshold_pass"] = not failures

    if args.json:
        print(json.dumps(aggregate, sort_keys=True, separators=(",", ":")))
    else:
        print(
            f"CONFIG S={args.sequence_length} D={args.dimension} "
            f"max_rows={args.max_rows or args.sequence_length} seeds={','.join(map(str, args.seeds))}"
        )
        for case in cases:
            print(
                f"seed={case['seed']} rows={case['rows']} "
                f"MAE={case['mae']:.8f} MaxAE={case['max_ae']:.8f} "
                f"MAE_LSB={case['mae_q88_lsb']:.4f} MaxAE_LSB={case['max_ae_q88_lsb']} "
                f"worst_row={case['worst_row']}"
            )
        print(
            f"SUMMARY mean_MAE={aggregate['mean_mae']:.8f} "
            f"worst_MaxAE={aggregate['worst_max_ae']:.8f} "
            f"mean_MAE_LSB={aggregate['mean_mae_q88_lsb']:.4f} "
            f"worst_MaxAE_LSB={aggregate['worst_max_ae_q88_lsb']}"
        )
        if args.require_mae is not None or args.require_maxae is not None:
            print(
                f"THRESHOLDS require_MAE={args.require_mae if args.require_mae is not None else float('inf'):.8f} "
                f"require_MaxAE={args.require_maxae if args.require_maxae is not None else float('inf'):.8f}"
            )
            for failure in failures:
                print(f"FAIL: {failure}")
            print("RESULT=FAIL" if failures else "RESULT=PASS")
        else:
            print("RESULT=PASS_EXECUTION_ONLY")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
