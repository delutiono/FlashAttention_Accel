#!/usr/bin/env python3
"""Print a lightweight S256 regression run manifest without creating artifacts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _path_text(path: Path) -> str:
    return path.as_posix()


def build_manifest(
    *,
    seed: int,
    sequence_length: int,
    dimension: int,
    kv_tile_rows: int,
    case_name: str,
    artifact_root: Path,
    run_dir: Path,
) -> dict[str, Any]:
    vector_dir = artifact_root / case_name
    cycle_model_json = run_dir / f"cycle_model_{case_name}_kv{kv_tile_rows}.json"
    compare_summary_json = run_dir / f"{case_name}_top_compare.json"
    dut_o_beats64 = run_dir / f"{case_name}_top_O_beats64.hex"
    metadata = vector_dir / f"{case_name}_metadata.json"
    simulator_log = run_dir / f"{case_name}_top_sim.log"
    genus_reports_dir = Path("synth/reports/fa_accel_top")
    genus_outputs_dir = Path("synth/outputs/fa_accel_top")
    ppa_summary_json = genus_reports_dir / "ppa_summary.json"

    return {
        "case_name": case_name,
        "config": {
            "seed": seed,
            "sequence_length": sequence_length,
            "dimension": dimension,
            "kv_tile_rows": kv_tile_rows,
            "stride_bytes": 128,
            "dut_dump_format": "beats64",
        },
        "artifact_policy": {
            "commit_vectors": False,
            "commit_run_outputs": False,
            "large_artifacts_root": _path_text(artifact_root.parent),
            "return_from_remote": [
                _path_text(compare_summary_json),
                _path_text(simulator_log),
                _path_text(cycle_model_json),
                _path_text(genus_reports_dir),
                _path_text(genus_outputs_dir),
                _path_text(ppa_summary_json),
            ],
            "return_only_on_mismatch": [
                _path_text(dut_o_beats64),
            ],
        },
        "artifact_paths": {
            "vector_dir": _path_text(vector_dir),
            "run_dir": _path_text(run_dir),
            "metadata_json": _path_text(metadata),
            "dut_o_beats64": _path_text(dut_o_beats64),
            "compare_summary_json": _path_text(compare_summary_json),
            "cycle_model_json": _path_text(cycle_model_json),
            "simulator_log": _path_text(simulator_log),
            "genus_reports_dir": _path_text(genus_reports_dir),
            "genus_outputs_dir": _path_text(genus_outputs_dir),
            "ppa_summary_json": _path_text(ppa_summary_json),
        },
        "commands": {
            "generate_vectors": (
                "python -B scripts/generate_test_vectors.py "
                f"--seed {seed} "
                f"--sequence-length {sequence_length} "
                f"--dimension {dimension} "
                f"--case-name {case_name} "
                f"--output-dir {_path_text(vector_dir)} "
                "--stride-bytes 128"
            ),
            "cycle_model_json": (
                "python -B scripts/cycle_bandwidth_model.py "
                f"--sequence-length {sequence_length} "
                f"--dimension {dimension} "
                f"--compute-rows {sequence_length} "
                f"--kv-tile-rows {kv_tile_rows} "
                f"--json > {_path_text(cycle_model_json)}"
            ),
            "compare_dut_beats64": (
                "python -B scripts/compare_vector_output.py "
                f"--metadata {_path_text(metadata)} "
                f"--dut-hex {_path_text(dut_o_beats64)} "
                "--format beats64 "
                "--require-mae 0 "
                "--require-maxae 0 "
                f"--dump-summary-json {_path_text(compare_summary_json)}"
            ),
            "parse_genus_ppa": (
                "python -B scripts/parse_genus_reports.py "
                f"{_path_text(genus_reports_dir)} "
                f"--json > {_path_text(ppa_summary_json)}"
            ),
        },
    }


def _build_manifest_from_args(args: argparse.Namespace) -> dict[str, Any]:
    run_dir = Path(args.run_dir) if args.run_dir is not None else Path("artifacts/runs") / args.case_name
    return build_manifest(
        seed=args.seed,
        sequence_length=args.sequence_length,
        dimension=args.dimension,
        kv_tile_rows=args.kv_tile_rows,
        case_name=args.case_name,
        artifact_root=Path(args.artifact_root),
        run_dir=run_dir,
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=100)
    parser.add_argument("--sequence-length", type=int, default=256)
    parser.add_argument("--dimension", type=int, default=64)
    parser.add_argument("--kv-tile-rows", type=int, default=16)
    parser.add_argument("--case-name", default="s256_d64_seed100")
    parser.add_argument("--artifact-root", default="artifacts/vectors")
    parser.add_argument("--run-dir", default=None)
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    manifest = _build_manifest_from_args(args)
    if args.json:
        print(json.dumps(manifest, indent=2, sort_keys=True))
    else:
        print(f"case_name: {manifest['case_name']}")
        print("artifact_paths:")
        for name, path in manifest["artifact_paths"].items():
            print(f"  {name}: {path}")
        print("artifact_policy:")
        for name, value in manifest["artifact_policy"].items():
            print(f"  {name}: {value}")
        print("commands:")
        for name, command in manifest["commands"].items():
            print(f"  {name}: {command}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
