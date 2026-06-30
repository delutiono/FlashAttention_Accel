#!/usr/bin/env python3
"""Unit tests for the baseline artifact status checker."""

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

from scripts.check_baseline_artifacts import build_status


def make_tmp_path() -> Path:
    tmp_parent = REPO_ROOT / "build" / "test_tmp"
    tmp_parent.mkdir(parents=True, exist_ok=True)
    path = tmp_parent / f"check_artifacts_{uuid.uuid4().hex}"
    path.mkdir()
    return path


class CheckBaselineArtifactsTest(unittest.TestCase):
    def test_empty_workspace_reports_required_remote_artifacts_missing(self) -> None:
        root = make_tmp_path()
        status = build_status(repo_root=root)

        self.assertFalse(status["baseline_ready"])
        self.assertEqual("s256_d64_seed100", status["case_name"])
        missing_paths = {item["path"] for item in status["missing_required_artifacts"]}

        self.assertIn(
            "artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json",
            missing_paths,
        )
        self.assertIn("synth/reports/fa_accel_top/ppa_summary.json", missing_paths)
        self.assertNotIn(
            "artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats128.hex",
            missing_paths,
        )

    def test_complete_minimum_remote_package_is_ready_without_dut_dump(self) -> None:
        root = make_tmp_path()
        required_paths = [
            root / "artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_compare.json",
            root / "artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_sim.log",
            root / "artifacts/runs/s256_d64_seed100/cycle_model_s256_d64_seed100_kv16.json",
            root / "synth/reports/fa_accel_top",
            root / "synth/outputs/fa_accel_top",
            root / "synth/reports/fa_accel_top/ppa_summary.json",
        ]
        for path in required_paths:
            if path.suffix:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("placeholder\n", encoding="utf-8")
            else:
                path.mkdir(parents=True, exist_ok=True)

        status = build_status(repo_root=root)

        self.assertTrue(status["baseline_ready"])
        self.assertEqual([], status["missing_required_artifacts"])
        optional_paths = {item["path"] for item in status["optional_debug_artifacts"]}
        self.assertIn(
            "artifacts/runs/s256_d64_seed100/s256_d64_seed100_top_O_beats128.hex",
            optional_paths,
        )

    def test_cli_json_reports_missing_state_without_creating_artifacts(self) -> None:
        root = make_tmp_path()
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "check_baseline_artifacts.py"),
                "--repo-root",
                str(root),
                "--json",
            ],
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["baseline_ready"])
        self.assertFalse((root / "artifacts").exists())
        self.assertFalse((root / "synth").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
