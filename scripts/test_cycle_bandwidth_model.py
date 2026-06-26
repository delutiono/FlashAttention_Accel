#!/usr/bin/env python3
"""Unit tests for the FlashAttention cycle/bandwidth estimator."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.cycle_bandwidth_model import DEFAULT_SCENARIOS, estimate_case


class CycleBandwidthModelTest(unittest.TestCase):
    def test_baseline_bytes_and_beats_use_stride128_and_64bit_axi(self) -> None:
        result = estimate_case(
            sequence_length=256,
            dimension=64,
            max_rows=None,
            stride_bytes=128,
            axi_data_width=64,
            mac_lanes=1,
            value_lanes=1,
            softmax_overhead_per_score=8,
            row_overhead=32,
            label="current_functional",
            cycle_budget=300_000,
        )
        self.assertEqual(256, result["output_rows"])
        self.assertEqual(256 * 128 * 3, result["read_bytes"])
        self.assertEqual(256 * 128, result["write_bytes"])
        self.assertEqual(256 * 16 * 3, result["read_beats"])
        self.assertEqual(256 * 16, result["write_beats"])
        self.assertEqual(256 * 257 // 2, result["causal_scores"])
        self.assertGreater(result["total_cycles"], 300_000)
        self.assertFalse(result["under_cycle_budget"])

    def test_target_parallel_parameters_fit_under_300k_cycles(self) -> None:
        result = estimate_case(
            sequence_length=256,
            dimension=64,
            max_rows=None,
            stride_bytes=128,
            axi_data_width=64,
            mac_lanes=16,
            value_lanes=16,
            softmax_overhead_per_score=2,
            row_overhead=16,
            label="target_parallel",
            cycle_budget=300_000,
        )
        self.assertLess(result["compute_cycles"], 300_000)
        self.assertLess(result["total_cycles"], 300_000)
        self.assertTrue(result["under_cycle_budget"])

    def test_max_rows_limits_output_and_causal_score_count(self) -> None:
        result = estimate_case(
            sequence_length=256,
            dimension=64,
            max_rows=8,
            stride_bytes=128,
            axi_data_width=64,
            mac_lanes=8,
            value_lanes=8,
            softmax_overhead_per_score=2,
            row_overhead=16,
            label="smoke",
            cycle_budget=300_000,
        )
        self.assertEqual(8, result["output_rows"])
        self.assertEqual(8 * 9 // 2, result["causal_scores"])
        self.assertEqual(256 * 128 * 3, result["read_bytes"])
        self.assertEqual(8 * 128, result["write_bytes"])
        self.assertEqual(8 * 16, result["write_beats"])

    def test_cli_json_emits_current_and_target_scenarios(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "cycle_bandwidth_model.py"),
                "--json",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(256, payload["config"]["sequence_length"])
        self.assertEqual(64, payload["config"]["dimension"])
        self.assertEqual(128, payload["config"]["stride_bytes"])
        self.assertEqual(64, payload["config"]["axi_data_width"])
        self.assertEqual([scenario["label"] for scenario in DEFAULT_SCENARIOS], [case["label"] for case in payload["scenarios"]])
        self.assertFalse(payload["scenarios"][0]["under_cycle_budget"])
        self.assertTrue(payload["scenarios"][1]["under_cycle_budget"])

    def test_cli_text_reports_budget_status(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "cycle_bandwidth_model.py"),
                "--sequence-length",
                "8",
                "--dimension",
                "8",
                "--max-rows",
                "4",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("CONFIG S=8 D=8 max_rows=4", result.stdout)
        self.assertIn("SCENARIO current_functional", result.stdout)
        self.assertIn("SCENARIO target_parallel", result.stdout)
        self.assertIn("under_300k=", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
