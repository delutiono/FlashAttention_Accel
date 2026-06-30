#!/usr/bin/env python3
"""Check whether the minimum remote S256 and Genus baseline artifacts exist."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.print_s256_regression_manifest import build_manifest


def _path_exists(repo_root: Path, path_text: str) -> bool:
    return (repo_root / Path(path_text)).exists()


def _artifact_entry(repo_root: Path, path_text: str, *, required: bool, kind: str) -> dict[str, Any]:
    return {
        "path": path_text,
        "kind": kind,
        "required": required,
        "present": _path_exists(repo_root, path_text),
    }


def _artifact_kind(path_text: str) -> str:
    if path_text.endswith("/"):
        return "directory"
    if path_text in {"synth/reports/fa_accel_top", "synth/outputs/fa_accel_top"}:
        return "directory"
    return "file"


def build_status(
    *,
    repo_root: Path,
    seed: int = 100,
    sequence_length: int = 256,
    dimension: int = 64,
    kv_tile_rows: int = 16,
    case_name: str = "s256_d64_seed100",
    artifact_root: Path = Path("artifacts/vectors"),
    run_dir: Path | None = None,
) -> dict[str, Any]:
    """Return a presence-only baseline artifact status.

    This intentionally does not read the large DUT O dump. That file is optional
    and should only be returned from remote runs when debugging a mismatch.
    """

    actual_run_dir = run_dir if run_dir is not None else Path("artifacts/runs") / case_name
    manifest = build_manifest(
        seed=seed,
        sequence_length=sequence_length,
        dimension=dimension,
        kv_tile_rows=kv_tile_rows,
        case_name=case_name,
        artifact_root=artifact_root,
        run_dir=actual_run_dir,
    )

    required_artifacts = [
        _artifact_entry(repo_root, path_text, required=True, kind=_artifact_kind(path_text))
        for path_text in manifest["artifact_policy"]["return_from_remote"]
    ]
    optional_debug_artifacts = [
        _artifact_entry(repo_root, path_text, required=False, kind=_artifact_kind(path_text))
        for path_text in manifest["artifact_policy"]["return_only_on_mismatch"]
    ]
    missing_required = [entry for entry in required_artifacts if not entry["present"]]

    return {
        "case_name": case_name,
        "config": manifest["config"],
        "baseline_ready": not missing_required,
        "required_artifacts": required_artifacts,
        "missing_required_artifacts": missing_required,
        "optional_debug_artifacts": optional_debug_artifacts,
        "signoff_note": (
            "Presence is necessary but not sufficient: inspect compare PASS, "
            "cycle-model fields, Genus reports, and check_design status before signoff."
        ),
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--seed", type=int, default=100)
    parser.add_argument("--sequence-length", type=int, default=256)
    parser.add_argument("--dimension", type=int, default=64)
    parser.add_argument("--kv-tile-rows", type=int, default=16)
    parser.add_argument("--case-name", default="s256_d64_seed100")
    parser.add_argument("--artifact-root", default="artifacts/vectors")
    parser.add_argument("--run-dir", default=None)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--require-complete", action="store_true")
    return parser.parse_args()


def _print_text(status: dict[str, Any]) -> None:
    ready = "yes" if status["baseline_ready"] else "no"
    print(f"case_name: {status['case_name']}")
    print(f"baseline_ready: {ready}")
    print("required_artifacts:")
    for entry in status["required_artifacts"]:
        state = "present" if entry["present"] else "missing"
        print(f"  [{state}] {entry['kind']} {entry['path']}")
    print("optional_debug_artifacts:")
    for entry in status["optional_debug_artifacts"]:
        state = "present" if entry["present"] else "missing"
        print(f"  [{state}] {entry['kind']} {entry['path']}")
    print(f"signoff_note: {status['signoff_note']}")


def main() -> int:
    args = _parse_args()
    status = build_status(
        repo_root=Path(args.repo_root),
        seed=args.seed,
        sequence_length=args.sequence_length,
        dimension=args.dimension,
        kv_tile_rows=args.kv_tile_rows,
        case_name=args.case_name,
        artifact_root=Path(args.artifact_root),
        run_dir=Path(args.run_dir) if args.run_dir is not None else None,
    )

    if args.json:
        print(json.dumps(status, indent=2, sort_keys=True))
    else:
        _print_text(status)

    if args.require_complete and not status["baseline_ready"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
