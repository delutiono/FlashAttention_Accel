#!/usr/bin/env python3
"""Unit tests for the S256 regression manifest printer."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.print_s256_regression_manifest import build_manifest


def make_tmp_path() -> Path:
    tmp_parent = REPO_ROOT / "build" / "test_tmp"
    tmp_parent.mkdir(parents=True, exist_ok=True)
    path = tmp_parent / f"print_manifest_{uuid.uuid4().hex}"
    path.mkdir()
    return path


class PrintS256RegressionManifestTest(unittest.TestCase):
    def test_default_manifest_paths_and_commands_are_json_serializable(self) -> None:
        manifest = build_manifest(
            seed=100,
            sequence_length=256,
            dimension=64,
            kv_tile_rows=16,
            case_name="s256_d64_seed100",
            artifact_root=Path("artifacts/vectors"),
            run_dir=Path("artifacts/runs/s256_d64_seed100"),
        )

        json.dumps(manifest, sort_keys=True)
        self.assertEqual("s256_d64_seed100", manifest["case_name"])
        self.assertEqual("artifacts/vectors/s256_d64_seed100", manifest["artifact_paths"]["vector_dir"])
        self.assertEqual("artifacts/runs/s256_d64_seed100", manifest["artifact_paths"]["run_dir"])
        self.assertEqual(
            "artifacts/vectors/s256_d64_seed100/s256_d64_seed100_metadata.json",
            manifest["artifact_paths"]["metadata_json"],
        )
        self.assertEqual(
            "artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats128.hex",
            manifest["artifact_paths"]["dut_o_beats128"],
        )
        self.assertEqual(
            "artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json",
            manifest["artifact_paths"]["compare_summary_json"],
        )
        self.assertIn("--output-dir artifacts/vectors/s256_d64_seed100", manifest["commands"]["generate_vectors"])
        self.assertIn("--kv-tile-rows 16", manifest["commands"]["cycle_model_json"])
        self.assertEqual("beats128", manifest["config"]["dut_dump_format"])
        self.assertIn("scripts/pack_vectors_128.py", manifest["commands"]["pack_vectors_128"])
        self.assertIn("--format beats128", manifest["commands"]["compare_dut_beats128"])
        self.assertIn("--dump-summary-json artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json", manifest["commands"]["compare_dut_beats128"])

    def test_kv_tile_rows_override_updates_cycle_model_command_and_path(self) -> None:
        manifest = build_manifest(
            seed=123,
            sequence_length=256,
            dimension=64,
            kv_tile_rows=32,
            case_name="s256_d64_seed123",
            artifact_root=Path("artifacts/custom_vectors"),
            run_dir=Path("artifacts/custom_runs/s256_d64_seed123"),
        )

        self.assertEqual(32, manifest["config"]["kv_tile_rows"])
        self.assertEqual(
            "artifacts/custom_runs/s256_d64_seed123/cycle_model_s256_d64_seed123_kv32.json",
            manifest["artifact_paths"]["cycle_model_json"],
        )
        self.assertIn("--seed 123", manifest["commands"]["generate_vectors"])
        self.assertIn("--case-name s256_d64_seed123", manifest["commands"]["generate_vectors"])
        self.assertIn("--kv-tile-rows 32", manifest["commands"]["cycle_model_json"])
        self.assertIn("cycle_model_s256_d64_seed123_kv32.json", manifest["commands"]["cycle_model_json"])

    def test_cli_json_does_not_create_artifacts(self) -> None:
        tmp_path = make_tmp_path()
        artifact_root = tmp_path / "vectors"
        run_dir = tmp_path / "runs" / "s256_d64_seed100"

        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "print_s256_regression_manifest.py"),
                "--json",
                "--artifact-root",
                str(artifact_root),
                "--run-dir",
                str(run_dir),
            ],
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual((artifact_root / "s256_d64_seed100").as_posix(), payload["artifact_paths"]["vector_dir"])
        self.assertFalse(artifact_root.exists())
        self.assertFalse(run_dir.exists())

    def test_cli_case_name_override_updates_default_run_dir(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "print_s256_regression_manifest.py"),
                "--json",
                "--seed",
                "123",
                "--case-name",
                "s256_d64_seed123",
            ],
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual("artifacts/runs/s256_d64_seed123", payload["artifact_paths"]["run_dir"])
        self.assertIn("artifacts/runs/s256_d64_seed123", payload["commands"]["compare_dut_beats128"])

    def test_remote_return_contract_lists_required_ppa_and_debug_artifacts(self) -> None:
        manifest = build_manifest(
            seed=100,
            sequence_length=256,
            dimension=64,
            kv_tile_rows=16,
            case_name="s256_d64_seed100",
            artifact_root=Path("artifacts/vectors"),
            run_dir=Path("artifacts/runs/s256_d64_seed100"),
        )

        paths = manifest["artifact_paths"]
        policy = manifest["artifact_policy"]

        self.assertEqual("synth/reports/fa_accel_top", paths["genus_reports_dir"])
        self.assertEqual("synth/outputs/fa_accel_top", paths["genus_outputs_dir"])
        self.assertEqual("synth/reports/fa_accel_top/ppa_summary.json", paths["ppa_summary_json"])

        self.assertEqual(
            [
                paths["compare_summary_json"],
                paths["simulator_log"],
                paths["cycle_model_json"],
                paths["genus_reports_dir"],
                paths["genus_outputs_dir"],
                paths["ppa_summary_json"],
            ],
            policy["return_from_remote"],
        )
        self.assertEqual([paths["dut_o_beats128"]], policy["return_only_on_mismatch"])
        self.assertFalse(policy["commit_vectors"])
        self.assertFalse(policy["commit_run_outputs"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
