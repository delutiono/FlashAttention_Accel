#!/usr/bin/env python3
"""Tests for the division-free reciprocal normalization/LUT/NR contract."""

from __future__ import annotations

import ast
import inspect
import json
import subprocess
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import model.recip_nr as recip_nr  # noqa: E402


class ReciprocalNrTest(unittest.TestCase):
    def test_analysis_cli_reports_distribution_corners_and_all_candidates(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "analyze_recip_nr.py"),
                "--seeds",
                "100",
                "--sequence-length",
                "8",
                "--dimension",
                "8",
                "--json",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(8, payload["denominators"]["count"])
        self.assertIn("histogram_power_of_two", payload["denominators"])
        self.assertIn("zero", payload["corner_cases"])
        self.assertEqual(8, len(payload["candidates"]))
        self.assertIn("exact_reciprocal", payload)
        self.assertTrue(
            all(candidate["elements"] == 64 for candidate in payload["candidates"])
        )
        self.assertTrue(
            all(
                "max_exact_final_delta_lsb" in candidate
                and "changed_exact_final_outputs" in candidate
                for candidate in payload["candidates"]
            )
        )

    def test_normalization_maps_u9_23_to_u1_31_without_value_loss(self) -> None:
        cases = (
            (0x00800000, 0x80000000, 0),
            (0x00FFFFFF, 0xFFFFFF00, 0),
            (0x01000000, 0x80000000, 1),
            (0x7FFFFFFF, 0xFFFFFFFE, 7),
            (0x80000000, 0x80000000, 8),
            (0xFFFFFFFF, 0xFFFFFFFF, 8),
        )
        for value, expected_mantissa, expected_exponent in cases:
            with self.subTest(value=f"0x{value:08X}"):
                normalized = recip_nr.normalize_u9_23(value)
                self.assertEqual(expected_mantissa, normalized.mantissa_u1_31)
                self.assertEqual(expected_exponent, normalized.exponent)

    def test_zero_input_is_flagged_and_obeys_the_normal_pipeline_latency(self) -> None:
        for iterations, expected_latency in ((1, 4), (2, 6)):
            trace = recip_nr.reciprocal_nr_trace(
                0,
                lut_entries=32,
                nr_iterations=iterations,
            )
            self.assertEqual(0, trace.reciprocal_u1_31)
            self.assertTrue(trace.divide_by_zero)
            self.assertEqual(expected_latency, trace.valid_latency)
            self.assertEqual((), trace.iterates_u1_31)

    def test_supported_lut_and_iteration_choices_are_frozen(self) -> None:
        for entries in (8, 16, 32, 64):
            for iterations in (1, 2):
                value = recip_nr.reciprocal_nr_u1_31(
                    0x00AF16AC,
                    lut_entries=entries,
                    nr_iterations=iterations,
                )
                self.assertGreater(value, 0)
        for entries in (0, 4, 12, 128):
            with self.assertRaises(ValueError):
                recip_nr.reciprocal_nr_u1_31(
                    0x00800000,
                    lut_entries=entries,
                    nr_iterations=1,
                )
        for iterations in (0, 3):
            with self.assertRaises(ValueError):
                recip_nr.reciprocal_nr_u1_31(
                    0x00800000,
                    lut_entries=32,
                    nr_iterations=iterations,
                )

    def test_lut_index_uses_the_top_fraction_bits_of_normalized_mantissa(self) -> None:
        for entries in (8, 16, 32, 64):
            self.assertEqual(0, recip_nr.seed_index_u1_31(0x80000000, entries))
            self.assertEqual(
                entries - 1,
                recip_nr.seed_index_u1_31(0xFFFFFFFF, entries),
            )

    def test_nr_trace_freezes_truncation_and_denormalization(self) -> None:
        trace = recip_nr.reciprocal_nr_trace(
            0x00AF16AC,
            lut_entries=32,
            nr_iterations=1,
        )
        self.assertEqual(0xAF16AC00, trace.normalized.mantissa_u1_31)
        self.assertEqual(0, trace.normalized.exponent)
        self.assertEqual(11, trace.seed_index)
        self.assertEqual(0x5E293206, trace.seed_u1_31)
        self.assertEqual((0x5D92640B,), trace.iterates_u1_31)
        self.assertEqual(0x5D92640B, trace.reciprocal_u1_31)
        self.assertFalse(trace.divide_by_zero)
        self.assertEqual(4, trace.valid_latency)

    def test_two_nr_iterations_are_never_less_accurate_than_one(self) -> None:
        numerator = 1 << 54
        denominators = (
            0x00800000,
            0x00800001,
            0x00AF16AC,
            0x00E14DA2,
            0x01000000,
            0x7FFFFFFF,
            0x80000000,
            0xFFFFFFFF,
        )
        for entries in (8, 16, 32, 64):
            for denominator in denominators:
                exact = (numerator + denominator // 2) // denominator
                one = recip_nr.reciprocal_nr_u1_31(
                    denominator,
                    lut_entries=entries,
                    nr_iterations=1,
                )
                two = recip_nr.reciprocal_nr_u1_31(
                    denominator,
                    lut_entries=entries,
                    nr_iterations=2,
                )
                self.assertLessEqual(abs(two - exact), abs(one - exact))

    def test_oracle_source_contains_no_variable_division_operator(self) -> None:
        tree = ast.parse(inspect.getsource(recip_nr))
        divisions = [
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.BinOp)
            and isinstance(node.op, (ast.Div, ast.FloorDiv))
        ]
        self.assertEqual([], divisions)


if __name__ == "__main__":
    unittest.main(verbosity=2)
