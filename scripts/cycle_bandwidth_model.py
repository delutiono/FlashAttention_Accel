#!/usr/bin/env python3
"""Simple cycle and bandwidth model for the baseline attention IP target."""

from __future__ import annotations

import argparse
import json
from typing import Any


DEFAULT_SEQUENCE_LENGTH = 256
DEFAULT_DIMENSION = 64
DEFAULT_STRIDE_BYTES = 128
DEFAULT_AXI_DATA_WIDTH = 64
DEFAULT_CYCLE_BUDGET = 300_000

DEFAULT_SCENARIOS: tuple[dict[str, int | str], ...] = (
    {
        "label": "current_functional",
        "mac_lanes": 1,
        "value_lanes": 1,
        "softmax_overhead_per_score": 8,
        "row_overhead": 32,
    },
    {
        "label": "target_parallel",
        "mac_lanes": 16,
        "value_lanes": 16,
        "softmax_overhead_per_score": 2,
        "row_overhead": 16,
    },
)


def _ceil_div(numerator: int, denominator: int) -> int:
    if denominator <= 0:
        raise ValueError("denominator must be positive")
    return (numerator + denominator - 1) // denominator


def _validate_config(
    *,
    sequence_length: int,
    dimension: int,
    max_rows: int | None,
    stride_bytes: int,
    axi_data_width: int,
) -> int:
    if sequence_length <= 0:
        raise ValueError("sequence_length must be positive")
    if dimension <= 0:
        raise ValueError("dimension must be positive")
    if max_rows is not None and max_rows <= 0:
        raise ValueError("max_rows must be positive when provided")
    if stride_bytes <= 0:
        raise ValueError("stride_bytes must be positive")
    if dimension * 2 > stride_bytes:
        raise ValueError("stride_bytes must cover one int16 row")
    if axi_data_width <= 0 or axi_data_width % 8 != 0:
        raise ValueError("axi_data_width must be a positive multiple of 8")
    return sequence_length if max_rows is None else min(sequence_length, max_rows)


def estimate_case(
    *,
    sequence_length: int = DEFAULT_SEQUENCE_LENGTH,
    dimension: int = DEFAULT_DIMENSION,
    max_rows: int | None = None,
    stride_bytes: int = DEFAULT_STRIDE_BYTES,
    axi_data_width: int = DEFAULT_AXI_DATA_WIDTH,
    mac_lanes: int,
    value_lanes: int,
    softmax_overhead_per_score: int,
    row_overhead: int,
    label: str,
    cycle_budget: int = DEFAULT_CYCLE_BUDGET,
) -> dict[str, Any]:
    """Estimate memory traffic and cycles for one implementation scenario."""

    output_rows = _validate_config(
        sequence_length=sequence_length,
        dimension=dimension,
        max_rows=max_rows,
        stride_bytes=stride_bytes,
        axi_data_width=axi_data_width,
    )
    if mac_lanes <= 0 or value_lanes <= 0:
        raise ValueError("lane counts must be positive")
    if softmax_overhead_per_score < 0 or row_overhead < 0:
        raise ValueError("cycle overheads must be nonnegative")

    beat_bytes = axi_data_width // 8
    beats_per_row = _ceil_div(stride_bytes, beat_bytes)
    causal_scores = output_rows * (output_rows + 1) // 2

    q_bytes = sequence_length * stride_bytes
    k_bytes = sequence_length * stride_bytes
    v_bytes = sequence_length * stride_bytes
    o_bytes = output_rows * stride_bytes
    read_bytes = q_bytes + k_bytes + v_bytes
    write_bytes = o_bytes

    qk_cycles_per_score = _ceil_div(dimension, mac_lanes)
    value_cycles_per_score = _ceil_div(dimension, value_lanes)
    score_pipeline_cycles = max(
        qk_cycles_per_score,
        value_cycles_per_score,
        softmax_overhead_per_score,
    )
    compute_cycles = causal_scores * score_pipeline_cycles + output_rows * row_overhead
    dma_cycles = (read_bytes + write_bytes) // beat_bytes
    total_cycles = compute_cycles + dma_cycles

    return {
        "label": label,
        "sequence_length": sequence_length,
        "dimension": dimension,
        "output_rows": output_rows,
        "stride_bytes": stride_bytes,
        "axi_data_width": axi_data_width,
        "beats_per_row": beats_per_row,
        "q_bytes": q_bytes,
        "k_bytes": k_bytes,
        "v_bytes": v_bytes,
        "read_bytes": read_bytes,
        "write_bytes": write_bytes,
        "read_beats": 3 * sequence_length * beats_per_row,
        "write_beats": output_rows * beats_per_row,
        "causal_scores": causal_scores,
        "mac_lanes": mac_lanes,
        "value_lanes": value_lanes,
        "softmax_overhead_per_score": softmax_overhead_per_score,
        "row_overhead": row_overhead,
        "qk_cycles_per_score": qk_cycles_per_score,
        "value_cycles_per_score": value_cycles_per_score,
        "score_pipeline_cycles": score_pipeline_cycles,
        "compute_cycles": compute_cycles,
        "dma_cycles": dma_cycles,
        "total_cycles": total_cycles,
        "cycle_budget": cycle_budget,
        "under_cycle_budget": total_cycles < cycle_budget,
    }


def build_report(
    *,
    sequence_length: int,
    dimension: int,
    max_rows: int | None,
    stride_bytes: int,
    axi_data_width: int,
    cycle_budget: int,
) -> dict[str, Any]:
    scenarios = [
        estimate_case(
            sequence_length=sequence_length,
            dimension=dimension,
            max_rows=max_rows,
            stride_bytes=stride_bytes,
            axi_data_width=axi_data_width,
            cycle_budget=cycle_budget,
            **scenario,
        )
        for scenario in DEFAULT_SCENARIOS
    ]
    return {
        "config": {
            "sequence_length": sequence_length,
            "dimension": dimension,
            "max_rows": max_rows,
            "stride_bytes": stride_bytes,
            "axi_data_width": axi_data_width,
            "cycle_budget": cycle_budget,
        },
        "assumptions": {
            "qkv_read_once": True,
            "o_write_rows": "max_rows if provided, otherwise S",
            "compute_model": "causal_scores * max(ceil(D/mac_lanes), ceil(D/value_lanes), softmax_overhead_per_score) + row overhead",
            "dma_model": "one cycle per AXI beat, added to compute cycles",
            "precision": "Q/K/V/O are signed int16 Q8.8 with stride padding",
        },
        "scenarios": scenarios,
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sequence-length", "-S", type=int, default=DEFAULT_SEQUENCE_LENGTH)
    parser.add_argument("--dimension", "-D", type=int, default=DEFAULT_DIMENSION)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--stride-bytes", type=int, default=DEFAULT_STRIDE_BYTES)
    parser.add_argument("--axi-data-width", type=int, default=DEFAULT_AXI_DATA_WIDTH)
    parser.add_argument("--cycle-budget", type=int, default=DEFAULT_CYCLE_BUDGET)
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    report = build_report(
        sequence_length=args.sequence_length,
        dimension=args.dimension,
        max_rows=args.max_rows,
        stride_bytes=args.stride_bytes,
        axi_data_width=args.axi_data_width,
        cycle_budget=args.cycle_budget,
    )
    if args.json:
        print(json.dumps(report, sort_keys=True))
    else:
        print(
            f"CONFIG S={args.sequence_length} D={args.dimension} "
            f"max_rows={args.max_rows if args.max_rows is not None else args.sequence_length} "
            f"stride={args.stride_bytes} AXI_DATA_W={args.axi_data_width} "
            f"cycle_budget={args.cycle_budget}"
        )
        for scenario in report["scenarios"]:
            print(
                f"SCENARIO {scenario['label']} "
                f"read_bytes={scenario['read_bytes']} write_bytes={scenario['write_bytes']} "
                f"read_beats={scenario['read_beats']} write_beats={scenario['write_beats']} "
                f"compute_cycles={scenario['compute_cycles']} dma_cycles={scenario['dma_cycles']} "
                f"total_cycles={scenario['total_cycles']} "
                f"under_300k={str(scenario['under_cycle_budget']).lower()}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
