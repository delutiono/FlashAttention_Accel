#!/usr/bin/env python3
"""Print a lightweight S256 regression run manifest without creating artifacts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def build_manifest(args: argparse.Namespace) -> dict[str, Any]:
    case_name = args.case_name
    vector_dir = Path(args.artifact_root) / case_name
    run_dir = Path(args.run_dir)
    cycle_model_json = run_dir / f"cycle_model_{case_name}_kv{args.kv_tile_rows}.json"
    compare_summary_json = run_dir / f"{case_name}_top_compare.json"
    dut_o_beats64 = run_dir / f"{case_name}_top_O_beats64.hex"
    metadata = vector_dir / f"{case_name}_metadata.json"

    return {
        "case_name": case_name,
        "vector_dir": str(vector_dir),
        "run_dir": str(run_dir),
        "cycle_model_json": str(cycle_model_json),
        "compare_summary_json": str(compare_summary_json),
        "commands": {
            "generate_vectors": (
                "python -B scripts/generate_test_vectors.py "
                f"--seed {args.seed} "
                f"--sequence-length {args.sequence_length} "
                f"--dimension {args.dimension} "
                f"--case-name {case_name} "
                f"--output-dir {vector_dir} "
                "--stride-bytes 128"
            ),
            "cycle_model_json": (
                "python -B scripts/cycle_bandwidth_model.py "
                f"--sequence-length {args.sequence_length} "
                f"--dimension {args.dimension} "
                f"--compute-rows {args.sequence_length} "
                f"--kv-tile-rows {args.kv_tile_rows} "
                f"--json > {cycle_model_json}"
            ),
            "compare_dut_beats64": (
                "python -B scripts/compare_vector_output.py "
                f"--metadata {metadata} "
                f"--dut-hex {dut_o_beats64} "
                "--format beats64 "
                "--require-mae 0 "
                "--require-maxae 0 "
                f"--dump-summary-json {compare_summary_json}"
            ),
        },
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=100)
    parser.add_argument("--sequence-length", type=int, default=256)
    parser.add_argument("--dimension", type=int, default=64)
    parser.add_argument("--kv-tile-rows", type=int, default=16)
    parser.add_argument("--case-name", default="s256_d64_seed100")
    parser.add_argument("--artifact-root", default="artifacts/vectors")
    parser.add_argument("--run-dir", default="artifacts/runs/s256_d64_seed100")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    manifest = build_manifest(args)
    if args.json:
        print(json.dumps(manifest, indent=2, sort_keys=True))
    else:
        print(f"case_name: {manifest['case_name']}")
        print(f"vector_dir: {manifest['vector_dir']}")
        print(f"run_dir: {manifest['run_dir']}")
        print(f"cycle_model_json: {manifest['cycle_model_json']}")
        print(f"compare_summary_json: {manifest['compare_summary_json']}")
        print("commands:")
        for name, command in manifest["commands"].items():
            print(f"  {name}: {command}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
