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

from model.golden_fixed import (  # noqa: E402
    DEFAULT_RECIP_LUT_ENTRIES,
    DEFAULT_RECIP_MODE,
    DEFAULT_RECIP_NR_ITERATIONS,
    RECIP_MODE_EXACT,
    RECIP_MODE_NR,
    SOFTMAX_SCORE_BITS,
    finalize_q88,
    reciprocal_u1_31,
    scaled_score_s32_16,
    softmax_row_fixed,
    wrap_signed,
)


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
    """Independent ideal-exp reference using the wrapped low-24 score contract."""

    row_count = len(q_rows) if max_rows is None else min(len(q_rows), max_rows)
    float_output: list[list[float]] = []
    q88_output: list[list[int]] = []

    for row_index in range(row_count):
        scores = [
            wrap_signed(
                scaled_score_s32_16(q_rows[row_index], k_rows[key_index]),
                SOFTMAX_SCORE_BITS,
            )
            / 65536.0
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


def _new_metrics() -> dict[str, int | float]:
    return {
        "elements": 0,
        "sum_float_error": 0.0,
        "max_ae": 0.0,
        "sum_lsb_error": 0,
        "max_ae_q88_lsb": 0,
    }


def _update_metrics(
    metrics: dict[str, int | float],
    output_q88: Sequence[int],
    reference_float: Sequence[float],
    reference_q88: Sequence[int],
) -> None:
    for output, ref_float, ref_q88 in zip(
        output_q88,
        reference_float,
        reference_q88,
    ):
        float_error = abs((output / 256.0) - ref_float)
        lsb_error = abs(output - ref_q88)
        metrics["elements"] = int(metrics["elements"]) + 1
        metrics["sum_float_error"] = float(metrics["sum_float_error"]) + float_error
        metrics["max_ae"] = max(float(metrics["max_ae"]), float_error)
        metrics["sum_lsb_error"] = int(metrics["sum_lsb_error"]) + lsb_error
        metrics["max_ae_q88_lsb"] = max(
            int(metrics["max_ae_q88_lsb"]),
            lsb_error,
        )


def _finish_metrics(metrics: dict[str, int | float]) -> dict[str, int | float]:
    count = int(metrics["elements"])
    return {
        "elements": count,
        "mae": float(metrics["sum_float_error"]) / count,
        "max_ae": float(metrics["max_ae"]),
        "mae_q88_lsb": float(metrics["sum_lsb_error"]) / count,
        "max_ae_q88_lsb": int(metrics["max_ae_q88_lsb"]),
    }


def run_case(
    seed: int,
    sequence_length: int,
    dimension: int,
    max_rows: int | None,
    recip_mode: str = DEFAULT_RECIP_MODE,
    recip_lut_entries: int = DEFAULT_RECIP_LUT_ENTRIES,
    recip_nr_iterations: int = DEFAULT_RECIP_NR_ITERATIONS,
) -> dict[str, object]:
    q_rows, k_rows, v_rows = generate_qkv(seed, sequence_length, dimension)
    reference_float, reference_q88 = ideal_attention_rows(q_rows, k_rows, v_rows, max_rows)

    candidate_metrics = _new_metrics()
    exact_metrics = _new_metrics()
    reciprocal_delta_sum = 0
    reciprocal_delta_max = 0
    reciprocal_changed = 0
    worst_row = 0
    row_count = len(reference_float)

    for row_index, (ref_float_row, ref_q88_row) in enumerate(
        zip(reference_float, reference_q88)
    ):
        state = softmax_row_fixed(
            q_rows[row_index],
            k_rows,
            v_rows,
            row_index,
            causal=True,
            recip_mode=recip_mode,
            recip_lut_entries=recip_lut_entries,
            recip_nr_iterations=recip_nr_iterations,
        )
        exact_reciprocal = reciprocal_u1_31(state.l_u9_23)
        exact_row = [
            finalize_q88(acc_value, exact_reciprocal)
            for acc_value in state.acc_s17_31
        ]
        _update_metrics(
            candidate_metrics,
            state.output_q88,
            ref_float_row,
            ref_q88_row,
        )
        _update_metrics(exact_metrics, exact_row, ref_float_row, ref_q88_row)
        row_max = 0.0
        for candidate_value, exact_value, ref_float_value in zip(
            state.output_q88,
            exact_row,
            ref_float_row,
        ):
            float_error = abs((candidate_value / 256.0) - ref_float_value)
            final_delta = abs(candidate_value - exact_value)
            reciprocal_delta_sum += final_delta
            reciprocal_delta_max = max(reciprocal_delta_max, final_delta)
            reciprocal_changed += int(final_delta != 0)
            row_max = max(row_max, float_error)
        if row_max >= float(candidate_metrics["max_ae"]):
            worst_row = row_index

    candidate = _finish_metrics(candidate_metrics)
    exact = _finish_metrics(exact_metrics)
    error_sources = {
        "pwl_fixed_vs_ideal": exact,
        "reciprocal_vs_exact": {
            "elements": int(candidate["elements"]),
            "mean_final_delta_lsb": reciprocal_delta_sum / int(candidate["elements"]),
            "max_final_delta_lsb": reciprocal_delta_max,
            "changed_outputs": reciprocal_changed,
        },
        "candidate_vs_ideal": candidate,
    }
    return {
        "seed": seed,
        "rows": row_count,
        **candidate,
        "worst_row": worst_row,
        "error_sources": error_sources,
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
        "--recip-mode",
        choices=(RECIP_MODE_NR, RECIP_MODE_EXACT),
        default=DEFAULT_RECIP_MODE,
    )
    parser.add_argument(
        "--recip-lut-entries",
        type=int,
        choices=(8, 16, 32, 64),
        default=DEFAULT_RECIP_LUT_ENTRIES,
    )
    parser.add_argument(
        "--recip-nr-iterations",
        type=int,
        choices=(1, 2),
        default=DEFAULT_RECIP_NR_ITERATIONS,
    )
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
    parser.add_argument(
        "--require-candidate-exact-max-lsb",
        type=int,
        default=None,
        help="Require candidate final output to stay within this many Q8.8 LSB of exact reciprocal finalization.",
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
    if (
        args.require_candidate_exact_max_lsb is not None
        and args.require_candidate_exact_max_lsb < 0
    ):
        parser.error("--require-candidate-exact-max-lsb must be nonnegative")

    cases = [
        run_case(
            seed,
            args.sequence_length,
            args.dimension,
            args.max_rows,
            args.recip_mode,
            args.recip_lut_entries,
            args.recip_nr_iterations,
        )
        for seed in args.seeds
    ]
    if args.recip_mode == RECIP_MODE_NR:
        reciprocal = {
            "mode": RECIP_MODE_NR,
            "lut_entries": args.recip_lut_entries,
            "nr_iterations": args.recip_nr_iterations,
            "valid_latency": 2 + (args.recip_nr_iterations << 1),
        }
    else:
        reciprocal = {
            "mode": RECIP_MODE_EXACT,
            "lut_entries": 0,
            "nr_iterations": 0,
            "valid_latency": 0,
        }
    element_count = sum(int(case["elements"]) for case in cases)
    exact_error = {
        "elements": element_count,
        "mae": sum(
            float(case["error_sources"]["pwl_fixed_vs_ideal"]["mae"])
            * int(case["elements"])
            for case in cases
        )
        / element_count,
        "max_ae": max(
            float(case["error_sources"]["pwl_fixed_vs_ideal"]["max_ae"])
            for case in cases
        ),
        "mae_q88_lsb": sum(
            float(case["error_sources"]["pwl_fixed_vs_ideal"]["mae_q88_lsb"])
            * int(case["elements"])
            for case in cases
        )
        / element_count,
        "max_ae_q88_lsb": max(
            int(case["error_sources"]["pwl_fixed_vs_ideal"]["max_ae_q88_lsb"])
            for case in cases
        ),
    }
    reciprocal_error = {
        "elements": element_count,
        "mean_final_delta_lsb": sum(
            float(case["error_sources"]["reciprocal_vs_exact"]["mean_final_delta_lsb"])
            * int(case["elements"])
            for case in cases
        )
        / element_count,
        "max_final_delta_lsb": max(
            int(case["error_sources"]["reciprocal_vs_exact"]["max_final_delta_lsb"])
            for case in cases
        ),
        "changed_outputs": sum(
            int(case["error_sources"]["reciprocal_vs_exact"]["changed_outputs"])
            for case in cases
        ),
    }
    aggregate = {
        "seeds": args.seeds,
        "sequence_length": args.sequence_length,
        "dimension": args.dimension,
        "max_rows": args.max_rows,
        "reciprocal": reciprocal,
        "cases": cases,
        "mean_mae": sum(float(case["mae"]) for case in cases) / len(cases),
        "worst_max_ae": max(float(case["max_ae"]) for case in cases),
        "mean_mae_q88_lsb": sum(float(case["mae_q88_lsb"]) for case in cases) / len(cases),
        "worst_max_ae_q88_lsb": max(int(case["max_ae_q88_lsb"]) for case in cases),
        "error_sources": {
            "pwl_fixed_vs_ideal": exact_error,
            "reciprocal_vs_exact": reciprocal_error,
            "candidate_vs_ideal": {
                "elements": element_count,
                "mae": sum(
                    float(case["mae"]) * int(case["elements"])
                    for case in cases
                )
                / element_count,
                "max_ae": max(float(case["max_ae"]) for case in cases),
                "mae_q88_lsb": sum(
                    float(case["mae_q88_lsb"]) * int(case["elements"])
                    for case in cases
                )
                / element_count,
                "max_ae_q88_lsb": max(
                    int(case["max_ae_q88_lsb"])
                    for case in cases
                ),
            },
        },
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
        final_delta = int(
            case["error_sources"]["reciprocal_vs_exact"]["max_final_delta_lsb"]
        )
        if (
            args.require_candidate_exact_max_lsb is not None
            and final_delta > args.require_candidate_exact_max_lsb
        ):
            failures.append(
                f"seed={case['seed']} candidate-vs-exact threshold exceeded: "
                f"MaxFinalDeltaLSB={final_delta} > "
                f"require_candidate_exact_max_lsb={args.require_candidate_exact_max_lsb}"
            )
    aggregate["require_mae"] = args.require_mae
    aggregate["require_maxae"] = args.require_maxae
    aggregate["require_candidate_exact_max_lsb"] = (
        args.require_candidate_exact_max_lsb
    )
    aggregate["threshold_pass"] = not failures

    if args.json:
        print(json.dumps(aggregate, sort_keys=True, separators=(",", ":")))
    else:
        print(
            f"CONFIG S={args.sequence_length} D={args.dimension} "
            f"max_rows={args.max_rows or args.sequence_length} seeds={','.join(map(str, args.seeds))} "
            f"recip_mode={reciprocal['mode']} LUT={reciprocal['lut_entries']} "
            f"iterations={reciprocal['nr_iterations']} latency={reciprocal['valid_latency']}"
        )
        for case in cases:
            print(
                f"seed={case['seed']} rows={case['rows']} "
                f"MAE={case['mae']:.8f} MaxAE={case['max_ae']:.8f} "
                f"MAE_LSB={case['mae_q88_lsb']:.4f} MaxAE_LSB={case['max_ae_q88_lsb']} "
                f"candidate_exact_MaxDeltaLSB="
                f"{case['error_sources']['reciprocal_vs_exact']['max_final_delta_lsb']} "
                f"worst_row={case['worst_row']}"
            )
        print(
            f"SUMMARY mean_MAE={aggregate['mean_mae']:.8f} "
            f"worst_MaxAE={aggregate['worst_max_ae']:.8f} "
            f"mean_MAE_LSB={aggregate['mean_mae_q88_lsb']:.4f} "
            f"worst_MaxAE_LSB={aggregate['worst_max_ae_q88_lsb']} "
            f"candidate_exact_mean_delta_LSB="
            f"{reciprocal_error['mean_final_delta_lsb']:.6f} "
            f"candidate_exact_max_delta_LSB={reciprocal_error['max_final_delta_lsb']} "
            f"candidate_exact_changed={reciprocal_error['changed_outputs']}"
        )
        print(
            f"ERROR_SOURCE pwl_fixed_vs_ideal "
            f"MAE={exact_error['mae']:.8f} MaxAE={exact_error['max_ae']:.8f}"
        )
        print(
            f"ERROR_SOURCE reciprocal_vs_exact "
            f"mean_delta_LSB={reciprocal_error['mean_final_delta_lsb']:.6f} "
            f"max_delta_LSB={reciprocal_error['max_final_delta_lsb']} "
            f"changed={reciprocal_error['changed_outputs']}"
        )
        if (
            args.require_mae is not None
            or args.require_maxae is not None
            or args.require_candidate_exact_max_lsb is not None
        ):
            print(
                f"THRESHOLDS require_MAE={args.require_mae if args.require_mae is not None else float('inf'):.8f} "
                f"require_MaxAE={args.require_maxae if args.require_maxae is not None else float('inf'):.8f} "
                f"require_candidate_exact_max_lsb="
                f"{args.require_candidate_exact_max_lsb if args.require_candidate_exact_max_lsb is not None else 'inf'}"
            )
            for failure in failures:
                print(f"FAIL: {failure}")
            print("RESULT=FAIL" if failures else "RESULT=PASS")
        else:
            print("RESULT=PASS_EXECUTION_ONLY")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
