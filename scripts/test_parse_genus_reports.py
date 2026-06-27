#!/usr/bin/env python3
"""Unit tests for Genus report parsing helpers."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.parse_genus_reports import parse_report_dir


class ParseGenusReportsTest(unittest.TestCase):
    def test_missing_reports_are_marked_without_crashing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = parse_report_dir(Path(tmp))

        self.assertEqual("missing", payload["reports"]["area"]["status"])
        self.assertEqual("missing", payload["reports"]["timing"]["status"])
        self.assertEqual("missing", payload["reports"]["power"]["status"])
        self.assertEqual("missing", payload["reports"]["qor"]["status"])
        self.assertEqual("missing", payload["reports"]["check_design"]["status"])
        self.assertFalse(payload["summary"]["check_design_clean"])

    def test_parses_area_timing_power_qor_and_clean_check_design(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            report_dir = Path(tmp)
            (report_dir / "area.rpt").write_text(
                "\n".join(
                    [
                        "Instance count: 42",
                        "Combinational area: 123.50",
                        "Noncombinational area: 45.25",
                        "Net area: 6.75",
                        "Total cell area: 168.75",
                    ]
                ),
                encoding="utf-8",
            )
            (report_dir / "timing.rpt").write_text(
                "\n".join(
                    [
                        "Path 1",
                        "slack (MET) 0.125",
                        "Path 2",
                        "slack (VIOLATED) -0.250",
                    ]
                ),
                encoding="utf-8",
            )
            (report_dir / "power.rpt").write_text(
                "Internal Power 1.5\nSwitching Power 2.25\nLeakage Power 0.125\nTotal Power 3.875\n",
                encoding="utf-8",
            )
            (report_dir / "qor.rpt").write_text(
                "WNS(ns): -0.25\nTNS(ns): -1.50\nViolating Paths: 3\nCell Area: 168.75\n",
                encoding="utf-8",
            )
            (report_dir / "check_design.rpt").write_text(
                "Check Design Summary\nWarnings: 0\nErrors: 0\n",
                encoding="utf-8",
            )

            payload = parse_report_dir(report_dir)

        self.assertEqual(42, payload["reports"]["area"]["instance_count"])
        self.assertEqual(123.50, payload["reports"]["area"]["combinational_area"])
        self.assertEqual(45.25, payload["reports"]["area"]["noncombinational_area"])
        self.assertEqual(6.75, payload["reports"]["area"]["net_area"])
        self.assertEqual(168.75, payload["reports"]["area"]["total_cell_area"])
        self.assertEqual(-0.250, payload["reports"]["timing"]["wns"])
        self.assertEqual(1, payload["reports"]["timing"]["violating_paths"])
        self.assertEqual(3.875, payload["reports"]["power"]["total_power"])
        self.assertEqual(-1.50, payload["reports"]["qor"]["tns"])
        self.assertTrue(payload["summary"]["check_design_clean"])
        self.assertEqual(168.75, payload["summary"]["area"])
        self.assertEqual(-0.25, payload["summary"]["wns"])
        self.assertEqual(3.875, payload["summary"]["total_power"])

    def test_require_clean_check_design_returns_nonzero_for_dirty_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            report_dir = Path(tmp)
            (report_dir / "check_design.rpt").write_text(
                "Check Design Summary\nWarnings: 2\nErrors: 1\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(REPO_ROOT / "scripts" / "parse_genus_reports.py"),
                    str(report_dir),
                    "--json",
                    "--require-clean-check-design",
                ],
                check=False,
                text=True,
                capture_output=True,
            )

        self.assertNotEqual(0, result.returncode)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["summary"]["check_design_clean"])
        self.assertEqual(1, payload["reports"]["check_design"]["error_count"])
        self.assertEqual(2, payload["reports"]["check_design"]["warning_count"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
