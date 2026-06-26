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
    compute_rows: int | None,
    kv_tile_rows: int | None,
    stride_bytes: int,
    axi_data_width: int,
) -> int:
    if sequence_length <= 0:
        raise ValueError("sequence_length must be positive")
    if dimension <= 0:
        raise ValueError("dimension must be positive")
    if max_rows is not None and max_rows <= 0:
        raise ValueError("max_rows must be positive when provided")
    if compute_rows is not None and compute_rows <= 0:
        raise ValueError("compute_rows must be positive when provided")
    if max_rows is not None and compute_rows is not None and max_rows != compute_rows:
        raise ValueError("max_rows and compute_rows must match when both are provided")
    if kv_tile_rows is not None and kv_tile_rows <= 0:
        raise ValueError("kv_tile_rows must be positive when provided")
    if stride_bytes <= 0:
        raise ValueError("stride_bytes must be positive")
    if dimension * 2 > stride_bytes:
        raise ValueError("stride_bytes must cover one int16 row")
    if axi_data_width <= 0 or axi_data_width % 8 != 0:
        raise ValueError("axi_data_width must be a positive multiple of 8")
    requested_rows = compute_rows if compute_rows is not None else max_rows
    return sequence_length if requested_rows is None else min(sequence_length, requested_rows)


def estimate_case(
    *,
    sequence_length: int = DEFAULT_SEQUENCE_LENGTH,
    dimension: int = DEFAULT_DIMENSION,
    max_rows: int | None = None,
    compute_rows: int | None = None,
    kv_tile_rows: int | None = None,
    reuse_kv_tile: bool = True,
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
        compute_rows=compute_rows,
        kv_tile_rows=kv_tile_rows,
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
    effective_compute_rows = output_rows
    effective_kv_tile_rows = kv_tile_rows if kv_tile_rows is not None else output_rows
    kv_tiles_per_compute = _ceil_div(output_rows, effective_kv_tile_rows)

    q_bytes = sequence_length * stride_bytes
    k_bytes = sequence_length * stride_bytes
    v_bytes = sequence_length * stride_bytes
    o_bytes = output_rows * stride_bytes
    write_bytes = o_bytes

    sequential_read_bytes = q_bytes + 2 * causal_scores * stride_bytes
    sequential_read_beats = q_bytes // beat_bytes + 2 * causal_scores * beats_per_row
    if kv_tile_rows is None:
        tile_reuse_kv_rows = sequence_length
    else:
        tile_reuse_kv_rows = output_rows
    tile_reuse_read_bytes = q_bytes + 2 * tile_reuse_kv_rows * stride_bytes
    tile_reuse_read_beats = q_bytes // beat_bytes + 2 * tile_reuse_kv_rows * beats_per_row

    read_bytes = tile_reuse_read_bytes if reuse_kv_tile else sequential_read_bytes
    read_beats = tile_reuse_read_beats if reuse_kv_tile else sequential_read_beats

    qk_cycles_per_score = _ceil_div(dimension, mac_lanes)
    value_cycles_per_score = _ceil_div(dimension, value_lanes)
    score_pipeline_cycles = max(
        qk_cycles_per_score,
        value_cycles_per_score,
        softmax_overhead_per_score,
    )
    compute_cycles = causal_scores * score_pipeline_cycles + output_rows * row_overhead
    sequential_dma_cycles = sequential_read_beats + output_rows * beats_per_row
    tile_reuse_dma_cycles = tile_reuse_read_beats + output_rows * beats_per_row
    dma_cycles = tile_reuse_dma_cycles if reuse_kv_tile else sequential_dma_cycles
    sequential_total_cycles = compute_cycles + sequential_dma_cycles
    tile_reuse_total_cycles = compute_cycles + tile_reuse_dma_cycles
    total_cycles = tile_reuse_total_cycles if reuse_kv_tile else sequential_total_cycles

    return {
        "label": label,
        "sequence_length": sequence_length,
        "dimension": dimension,
        "output_rows": output_rows,
        "compute_rows": effective_compute_rows,
        "kv_tile_rows": effective_kv_tile_rows,
        "reuse_kv_tile": reuse_kv_tile,
        "kv_tiles_per_compute": kv_tiles_per_compute,
        "stride_bytes": stride_bytes,
        "axi_data_width": axi_data_width,
        "beats_per_row": beats_per_row,
        "q_bytes": q_bytes,
        "k_bytes": k_bytes,
        "v_bytes": v_bytes,
        "read_bytes": read_bytes,
        "write_bytes": write_bytes,
        "read_beats": read_beats,
        "write_beats": output_rows * beats_per_row,
        "sequential_read_bytes": sequential_read_bytes,
        "sequential_read_beats": sequential_read_beats,
        "sequential_dma_cycles": sequential_dma_cycles,
        "sequential_total_cycles": sequential_total_cycles,
        "tile_reuse_read_bytes": tile_reuse_read_bytes,
        "tile_reuse_read_beats": tile_reuse_read_beats,
        "tile_reuse_dma_cycles": tile_reuse_dma_cycles,
        "tile_reuse_total_cycles": tile_reuse_total_cycles,
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
    compute_rows: int | None = None,
    kv_tile_rows: int | None = None,
    reuse_kv_tile: bool = True,
    stride_bytes: int,
    axi_data_width: int,
    cycle_budget: int,
) -> dict[str, Any]:
    effective_compute_rows = sequence_length if compute_rows is None and max_rows is None else (compute_rows if compute_rows is not None else max_rows)
    scenarios = [
        estimate_case(
            sequence_length=sequence_length,
            dimension=dimension,
            max_rows=max_rows,
            compute_rows=compute_rows,
            kv_tile_rows=kv_tile_rows,
            reuse_kv_tile=reuse_kv_tile,
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
            "compute_rows": effective_compute_rows,
            "kv_tile_rows": kv_tile_rows,
            "reuse_kv_tile": reuse_kv_tile,
            "stride_bytes": stride_bytes,
            "axi_data_width": axi_data_width,
            "cycle_budget": cycle_budget,
        },
        "assumptions": {
            "qkv_read_once": "reported as tile_reuse_*; active read_* uses reuse_kv_tile",
            "o_write_rows": "compute_rows/max_rows if provided, otherwise S",
            "sequential_traffic": "Q read once, K/V read for every causal score without tile reuse",
            "tile_reuse_traffic": "Q read once, K/V rows read once across kv_tile_rows chunks for the compute_rows output tile",
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
    parser.add_argument("--compute-rows", type=int, default=None)
    parser.add_argument("--kv-tile-rows", type=int, default=None)
    parser.add_argument("--reuse-kv-tile", dest="reuse_kv_tile", action="store_true", default=True)
    parser.add_argument("--no-reuse-kv-tile", dest="reuse_kv_tile", action="store_false")
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
        compute_rows=args.compute_rows,
        kv_tile_rows=args.kv_tile_rows,
        reuse_kv_tile=args.reuse_kv_tile,
        stride_bytes=args.stride_bytes,
        axi_data_width=args.axi_data_width,
        cycle_budget=args.cycle_budget,
    )
    if args.json:
        print(json.dumps(report, sort_keys=True))
    else:
        print(
            f"CONFIG S={args.sequence_length} D={args.dimension} "
            f"compute_rows={args.compute_rows if args.compute_rows is not None else (args.max_rows if args.max_rows is not None else args.sequence_length)} "
            f"max_rows={args.max_rows if args.max_rows is not None else args.sequence_length} "
            f"kv_tile_rows={args.kv_tile_rows if args.kv_tile_rows is not None else 'auto'} "
            f"reuse_kv_tile={str(args.reuse_kv_tile).lower()} "
            f"stride={args.stride_bytes} AXI_DATA_W={args.axi_data_width} "
            f"cycle_budget={args.cycle_budget}"
        )
        for scenario in report["scenarios"]:
            print(
                f"SCENARIO {scenario['label']} "
                f"read_bytes={scenario['read_bytes']} write_bytes={scenario['write_bytes']} "
                f"read_beats={scenario['read_beats']} write_beats={scenario['write_beats']} "
                f"sequential_read_bytes={scenario['sequential_read_bytes']} "
                f"tile_reuse_read_bytes={scenario['tile_reuse_read_bytes']} "
                f"kv_tiles_per_compute={scenario['kv_tiles_per_compute']} "
                f"compute_cycles={scenario['compute_cycles']} dma_cycles={scenario['dma_cycles']} "
                f"sequential_total_cycles={scenario['sequential_total_cycles']} "
                f"tile_reuse_total_cycles={scenario['tile_reuse_total_cycles']} "
                f"total_cycles={scenario['total_cycles']} "
                f"under_300k={str(scenario['under_cycle_budget']).lower()}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
