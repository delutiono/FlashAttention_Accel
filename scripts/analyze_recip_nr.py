#!/usr/bin/env python3
"""Sweep reciprocal LUT/NR candidates on the current fixed-point model."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from model.golden_fixed import (  # noqa: E402
    finalize_q88,
    reciprocal_u1_31,
    softmax_row_fixed,
)
from model.recip_nr import (  # noqa: E402
    SUPPORTED_LUT_ENTRIES,
    SUPPORTED_NR_ITERATIONS,
    reciprocal_nr_trace,
    reciprocal_nr_u1_31,
)
from scripts.run_numeric_regression import (  # noqa: E402
    generate_qkv,
    ideal_attention_rows,
)


RECIP_NUMERATOR = 1 << 54


def _parse_seeds(text: str) -> list[int]:
    seeds = [int(item.strip()) for item in text.split(",") if item.strip()]
    if not seeds:
        raise argparse.ArgumentTypeError("at least one seed is required")
    return seeds


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
        metrics["sum_float_error"] = (
            float(metrics["sum_float_error"]) + float_error
        )
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


def _percentile(sorted_values: Sequence[int], percentile: int) -> int:
    if not sorted_values:
        raise ValueError("percentile input must be nonempty")
    index = ((len(sorted_values) - 1) * percentile + 50) // 100
    return sorted_values[index]


def summarize_denominators(values: Sequence[int]) -> dict[str, object]:
    sorted_values = sorted(values)
    histogram: dict[str, int] = {}
    for value in values:
        exponent = (value.bit_length() - 1) - 23
        label = f"[2^{exponent},2^{exponent + 1})"
        histogram[label] = histogram.get(label, 0) + 1
    return {
        "count": len(values),
        "min_u9_23": min(values),
        "min_hex": f"{min(values):08X}",
        "min_value": min(values) / float(1 << 23),
        "max_u9_23": max(values),
        "max_hex": f"{max(values):08X}",
        "max_value": max(values) / float(1 << 23),
        "p50_value": _percentile(sorted_values, 50) / float(1 << 23),
        "p90_value": _percentile(sorted_values, 90) / float(1 << 23),
        "p99_value": _percentile(sorted_values, 99) / float(1 << 23),
        "histogram_power_of_two": histogram,
    }


def corner_case_report() -> dict[str, object]:
    cases = {
        "zero": 0,
        "one": 0x00800000,
        "below_two": 0x00FFFFFF,
        "two": 0x01000000,
        "below_256": 0x7FFFFFFF,
        "256": 0x80000000,
        "u32_max": 0xFFFFFFFF,
    }
    report: dict[str, object] = {}
    for name, value in cases.items():
        trace = reciprocal_nr_trace(
            value,
            lut_entries=32,
            nr_iterations=1,
        )
        exact = None if value == 0 else reciprocal_u1_31(value)
        report[name] = {
            "input_u9_23": value,
            "input_hex": f"{value:08X}",
            "exact_u1_31": exact,
            "nr_u1_31": trace.reciprocal_u1_31,
            "nr_hex": f"{trace.reciprocal_u1_31:08X}",
            "divide_by_zero": trace.divide_by_zero,
            "normalized_hex": f"{trace.normalized.mantissa_u1_31:08X}",
            "exponent": trace.normalized.exponent,
            "seed_index": trace.seed_index,
            "valid_latency": trace.valid_latency,
        }
    return report


def analyze(
    seeds: Sequence[int],
    sequence_length: int,
    dimension: int,
    require_mae: float,
    require_maxae: float,
) -> dict[str, object]:
    configs = [
        (entries, iterations)
        for entries in SUPPORTED_LUT_ENTRIES
        for iterations in SUPPORTED_NR_ITERATIONS
    ]
    aggregate_metrics = {config: _new_metrics() for config in configs}
    exact_aggregate = _new_metrics()
    per_seed = {config: [] for config in configs}
    exact_cases = []
    reciprocal_errors = {
        config: {
            "count": 0,
            "sum_abs_lsb": 0,
            "max_abs_lsb": 0,
            "max_relative": 0.0,
            "sum_exact_final_delta_lsb": 0,
            "max_exact_final_delta_lsb": 0,
            "changed_exact_final_outputs": 0,
        }
        for config in configs
    }
    denominators = []

    for seed in seeds:
        q_rows, k_rows, v_rows = generate_qkv(
            seed,
            sequence_length,
            dimension,
        )
        reference_float, reference_q88 = ideal_attention_rows(
            q_rows,
            k_rows,
            v_rows,
            max_rows=None,
        )
        seed_metrics = {config: _new_metrics() for config in configs}
        exact_seed_metrics = _new_metrics()

        for row_index in range(sequence_length):
            state = softmax_row_fixed(
                q_rows[row_index],
                k_rows,
                v_rows,
                row_index,
                causal=True,
            )
            denominators.append(state.l_u9_23)
            _update_metrics(
                exact_seed_metrics,
                state.output_q88,
                reference_float[row_index],
                reference_q88[row_index],
            )
            _update_metrics(
                exact_aggregate,
                state.output_q88,
                reference_float[row_index],
                reference_q88[row_index],
            )
            exact_recip = reciprocal_u1_31(state.l_u9_23)

            for config in configs:
                entries, iterations = config
                candidate_recip = reciprocal_nr_u1_31(
                    state.l_u9_23,
                    lut_entries=entries,
                    nr_iterations=iterations,
                )
                output = [
                    finalize_q88(acc_value, candidate_recip)
                    for acc_value in state.acc_s17_31
                ]
                _update_metrics(
                    seed_metrics[config],
                    output,
                    reference_float[row_index],
                    reference_q88[row_index],
                )
                _update_metrics(
                    aggregate_metrics[config],
                    output,
                    reference_float[row_index],
                    reference_q88[row_index],
                )
                abs_lsb = abs(candidate_recip - exact_recip)
                error = reciprocal_errors[config]
                error["count"] = int(error["count"]) + 1
                error["sum_abs_lsb"] = int(error["sum_abs_lsb"]) + abs_lsb
                error["max_abs_lsb"] = max(int(error["max_abs_lsb"]), abs_lsb)
                error["max_relative"] = max(
                    float(error["max_relative"]),
                    abs_lsb / exact_recip,
                )
                for candidate_value, exact_value in zip(
                    output,
                    state.output_q88,
                ):
                    final_delta = abs(candidate_value - exact_value)
                    error["sum_exact_final_delta_lsb"] = (
                        int(error["sum_exact_final_delta_lsb"]) + final_delta
                    )
                    error["max_exact_final_delta_lsb"] = max(
                        int(error["max_exact_final_delta_lsb"]),
                        final_delta,
                    )
                    if final_delta:
                        error["changed_exact_final_outputs"] = (
                            int(error["changed_exact_final_outputs"]) + 1
                        )

        exact_case = _finish_metrics(exact_seed_metrics)
        exact_case["seed"] = seed
        exact_cases.append(exact_case)
        for config in configs:
            case = _finish_metrics(seed_metrics[config])
            case["seed"] = seed
            per_seed[config].append(case)

    candidates = []
    for config in configs:
        entries, iterations = config
        final_metrics = _finish_metrics(aggregate_metrics[config])
        error = reciprocal_errors[config]
        cases = per_seed[config]
        final_metrics.update(
            {
                "lut_entries": entries,
                "nr_iterations": iterations,
                "valid_latency": 2 + (iterations << 1),
                "cases": cases,
                "recip_mean_abs_lsb": (
                    int(error["sum_abs_lsb"]) / int(error["count"])
                ),
                "recip_max_abs_lsb": int(error["max_abs_lsb"]),
                "recip_max_relative": float(error["max_relative"]),
                "mean_exact_final_delta_lsb": (
                    int(error["sum_exact_final_delta_lsb"])
                    / int(final_metrics["elements"])
                ),
                "max_exact_final_delta_lsb": int(
                    error["max_exact_final_delta_lsb"]
                ),
                "changed_exact_final_outputs": int(
                    error["changed_exact_final_outputs"]
                ),
                "threshold_pass": all(
                    float(case["mae"]) <= require_mae
                    and float(case["max_ae"]) <= require_maxae
                    for case in cases
                ),
            }
        )
        candidates.append(final_metrics)

    exact = _finish_metrics(exact_aggregate)
    exact["cases"] = exact_cases
    return {
        "seeds": list(seeds),
        "sequence_length": sequence_length,
        "dimension": dimension,
        "thresholds": {
            "mae": require_mae,
            "max_ae": require_maxae,
        },
        "denominators": summarize_denominators(denominators),
        "corner_cases": corner_case_report(),
        "exact_reciprocal": exact,
        "candidates": candidates,
    }


def _print_text(payload: dict[str, object]) -> None:
    denominators = payload["denominators"]
    assert isinstance(denominators, dict)
    print(
        f"CONFIG S={payload['sequence_length']} D={payload['dimension']} "
        f"seeds={','.join(map(str, payload['seeds']))}"
    )
    print(
        f"DENOM count={denominators['count']} "
        f"min={denominators['min_value']:.8f}({denominators['min_hex']}) "
        f"max={denominators['max_value']:.8f}({denominators['max_hex']}) "
        f"p50={denominators['p50_value']:.8f} "
        f"p90={denominators['p90_value']:.8f} "
        f"p99={denominators['p99_value']:.8f}"
    )
    print(f"HIST {json.dumps(denominators['histogram_power_of_two'], sort_keys=True)}")
    exact = payload["exact_reciprocal"]
    assert isinstance(exact, dict)
    print(
        f"EXACT MAE={exact['mae']:.8f} MaxAE={exact['max_ae']:.8f} "
        f"MAE_LSB={exact['mae_q88_lsb']:.4f} "
        f"MaxAE_LSB={exact['max_ae_q88_lsb']}"
    )
    candidates = payload["candidates"]
    assert isinstance(candidates, list)
    for candidate in candidates:
        assert isinstance(candidate, dict)
        print(
            f"LUT={candidate['lut_entries']:2d} NR={candidate['nr_iterations']} "
            f"latency={candidate['valid_latency']} "
            f"MAE={candidate['mae']:.8f} MaxAE={candidate['max_ae']:.8f} "
            f"recip_mean_lsb={candidate['recip_mean_abs_lsb']:.3f} "
            f"recip_max_lsb={candidate['recip_max_abs_lsb']} "
            f"recip_max_rel={candidate['recip_max_relative']:.9f} "
            f"final_delta_mean_lsb={candidate['mean_exact_final_delta_lsb']:.6f} "
            f"final_delta_max_lsb={candidate['max_exact_final_delta_lsb']} "
            f"final_changed={candidate['changed_exact_final_outputs']} "
            f"threshold_pass={int(candidate['threshold_pass'])}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--seeds",
        type=_parse_seeds,
        default=_parse_seeds("100,101,102,103,104"),
    )
    parser.add_argument("--sequence-length", type=int, default=256)
    parser.add_argument("--dimension", type=int, default=64)
    parser.add_argument("--require-mae", type=float, default=0.03)
    parser.add_argument("--require-maxae", type=float, default=0.10)
    parser.add_argument("--enforce-thresholds", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if args.sequence_length <= 0 or args.dimension <= 0:
        parser.error("sequence length and dimension must be positive")
    if args.require_mae < 0 or args.require_maxae < 0:
        parser.error("error thresholds must be nonnegative")

    payload = analyze(
        args.seeds,
        args.sequence_length,
        args.dimension,
        args.require_mae,
        args.require_maxae,
    )
    if args.json:
        print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    else:
        _print_text(payload)

    if args.enforce_thresholds:
        candidates = payload["candidates"]
        assert isinstance(candidates, list)
        return 0 if all(candidate["threshold_pass"] for candidate in candidates) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
