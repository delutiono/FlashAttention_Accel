#!/usr/bin/env python3
"""Unit tests for the current RTL pure-integer oracle."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import model.golden_fixed as golden_fixed  # noqa: E402
from model.golden_fixed import (  # noqa: E402
    EXP_ONE_U1_23,
    exp_pwl_u1_23,
    finalize_q88,
    reciprocal_u1_31,
    round_half_away_div,
    saturate_int16,
    scaled_score_s32_16,
    softmax_row_fixed,
)


class FixedGoldenTest(unittest.TestCase):
    def test_numeric_regression_cli_thresholds_pass_with_zero_exit(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "run_numeric_regression.py"),
                "--seeds",
                "7,8,9",
                "--sequence-length",
                "8",
                "--dimension",
                "8",
                "--require-mae",
                "1.0",
                "--require-maxae",
                "3.0",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("RESULT=PASS", result.stdout)
        self.assertIn("require_MAE=1.00000000", result.stdout)
        self.assertIn("require_MaxAE=3.00000000", result.stdout)

    def test_numeric_regression_cli_threshold_failure_is_explicit_and_nonzero(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "run_numeric_regression.py"),
                "--seeds",
                "7,8,9",
                "--sequence-length",
                "8",
                "--dimension",
                "8",
                "--require-mae",
                "0",
                "--require-maxae",
                "0",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("RESULT=FAIL", result.stdout)
        self.assertIn("MAE threshold exceeded", result.stdout)
        self.assertIn("MaxAE threshold exceeded", result.stdout)

    def test_numeric_regression_cli_applies_thresholds_to_each_seed(self) -> None:
        base_command = [
            sys.executable,
            "-B",
            str(REPO_ROOT / "scripts" / "run_numeric_regression.py"),
            "--seeds",
            "7,8,9",
            "--sequence-length",
            "8",
            "--dimension",
            "8",
        ]
        measured = subprocess.run(
            [*base_command, "--json"],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, measured.returncode, measured.stderr)
        payload = json.loads(measured.stdout)
        mae_values = [case["mae"] for case in payload["cases"]]
        maxae_values = [case["max_ae"] for case in payload["cases"]]
        mae_limit = (payload["mean_mae"] + max(mae_values)) / 2.0
        maxae_limit = (min(maxae_values) + max(maxae_values)) / 2.0

        checked = subprocess.run(
            [
                *base_command,
                "--require-mae",
                f"{mae_limit:.12f}",
                "--require-maxae",
                f"{maxae_limit:.12f}",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(0, checked.returncode)
        self.assertRegex(checked.stdout, r"FAIL: seed=\d+ MAE threshold exceeded")
        self.assertRegex(checked.stdout, r"FAIL: seed=\d+ MaxAE threshold exceeded")

    def test_numeric_regression_cli_is_reproducible_and_honors_max_rows(self) -> None:
        command = [
            sys.executable,
            str(REPO_ROOT / "scripts" / "run_numeric_regression.py"),
            "--seeds",
            "7,8,9",
            "--sequence-length",
            "8",
            "--dimension",
            "8",
            "--max-rows",
            "4",
            "--json",
        ]
        first = subprocess.run(command, check=False, text=True, capture_output=True)
        second = subprocess.run(command, check=False, text=True, capture_output=True)
        self.assertEqual(0, first.returncode, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        result = json.loads(first.stdout)
        self.assertEqual([7, 8, 9], [case["seed"] for case in result["cases"]])
        self.assertTrue(all(case["rows"] == 4 for case in result["cases"]))
        self.assertTrue(any(case["max_ae_q88_lsb"] > 0 for case in result["cases"]))

    def test_score_is_exact_raw_dot_arithmetic_shift_three(self) -> None:
        self.assertEqual(2, scaled_score_s32_16([17], [1]))
        self.assertEqual(-2, scaled_score_s32_16([-9], [1]))
        self.assertEqual((256 * -3072) >> 3, scaled_score_s32_16([256], [-3072]))

    def test_rtl_container_wrap_and_truncation_widths(self) -> None:
        self.assertTrue(hasattr(golden_fixed, "wrap_signed"))
        self.assertTrue(hasattr(golden_fixed, "wrap_unsigned"))
        wrap_signed = golden_fixed.wrap_signed
        wrap_unsigned = golden_fixed.wrap_unsigned
        self.assertEqual(-(1 << 47), wrap_signed(1 << 47, 48))
        self.assertEqual(5, wrap_signed((1 << 48) + 5, 48))
        self.assertEqual(-65536, wrap_signed(0xFF0000, 24))
        self.assertEqual(0xFFFFFFFF, wrap_unsigned((1 << 32) - 1, 32))
        self.assertEqual(0, wrap_unsigned(1 << 32, 32))

        wrapped_recip = wrap_unsigned(
            ((1 << 31) * (1 << 23) + 1 // 2) // 1,
            32,
        )
        self.assertEqual(wrapped_recip, reciprocal_u1_31(1))

    def test_exp_pwl_known_and_generic_points_include_negative_one_point_five(self) -> None:
        self.assertEqual(0x800000, exp_pwl_u1_23(0))
        self.assertEqual(0x4DA2CC, exp_pwl_u1_23(-32768))
        self.assertEqual(0x2F16AC, exp_pwl_u1_23(-65536))
        self.assertEqual(0x1C8F87, exp_pwl_u1_23(-98304))
        self.assertEqual(0x1152AB, exp_pwl_u1_23(-131072))
        self.assertEqual(0, exp_pwl_u1_23(-16 * 65536))
        self.assertEqual(
            0x25D319,
            exp_pwl_u1_23(-81920),
        )

    def test_exp_pwl_tail_matches_current_rtl_exact_constants(self) -> None:
        self.assertEqual(0x022627, exp_pwl_u1_23(-5 * 65536))
        self.assertEqual(0x01901D, exp_pwl_u1_23(-8 * 65536))
        self.assertEqual(0x00C80E, exp_pwl_u1_23(-12 * 65536))

    def test_exp_pwl_uses_full_s16_fraction_not_an_s88_grid(self) -> None:
        self.assertEqual(0x025812, exp_pwl_u1_23(-262272))
        self.assertNotEqual(
            exp_pwl_u1_23(-262144),
            exp_pwl_u1_23(-262272),
        )

    def test_reciprocal_uses_integer_formula_for_any_nonzero_l(self) -> None:
        numerator = (1 << 31) * (1 << 23)
        for l_value in (1, 3, 0x00800000, 0x00AF16AC, 0x01000000, 0x7FFFFFFF):
            expected = ((numerator + l_value // 2) // l_value) & 0xFFFFFFFF
            self.assertEqual(expected, reciprocal_u1_31(l_value))
        with self.assertRaises(ValueError):
            reciprocal_u1_31(0)

    def test_half_away_rounding_and_int16_saturation(self) -> None:
        self.assertEqual(2, round_half_away_div(3, 2))
        self.assertEqual(-2, round_half_away_div(-3, 2))
        self.assertEqual(1, round_half_away_div(1, 2))
        self.assertEqual(-1, round_half_away_div(-1, 2))
        self.assertEqual(32767, saturate_int16(40000))
        self.assertEqual(-32768, saturate_int16(-40000))
        self.assertEqual(32767, finalize_q88(32768 << 31, 1 << 31))
        self.assertEqual(-32768, finalize_q88(-32769 << 31, 1 << 31))

    def test_causal_row_integer_online_update_ignores_future_keys(self) -> None:
        state = softmax_row_fixed(
            q_row=[0],
            k_rows=[[0], [32767]],
            v_rows=[[256, -256], [32767, 32767]],
            row_index=0,
            causal=True,
        )
        self.assertEqual(0, state.m_s32_16)
        self.assertEqual(EXP_ONE_U1_23, state.l_u9_23)
        self.assertEqual([256 << 23, -256 << 23], state.acc_s17_31)
        self.assertEqual([256, -256], state.output_q88)

    def test_causal_row_lower_by_one_point_five_updates_with_integer_pwl(self) -> None:
        state = softmax_row_fixed(
            q_row=[256],
            k_rows=[[0], [-3072], [32767]],
            v_rows=[[256], [512], [32767]],
            row_index=1,
            causal=True,
        )
        p = 0x1C8F87
        self.assertEqual(0, state.m_s32_16)
        self.assertEqual(EXP_ONE_U1_23 + p, state.l_u9_23)
        self.assertEqual([(256 * EXP_ONE_U1_23) + (512 * p)], state.acc_s17_31)
        expected_recip = reciprocal_u1_31(EXP_ONE_U1_23 + p)
        self.assertEqual(
            [finalize_q88((256 * EXP_ONE_U1_23) + (512 * p), expected_recip)],
            state.output_q88,
        )

    def test_softmax_consumes_low_signed_24_bits_of_score_pipe(self) -> None:
        state = softmax_row_fixed(
            q_row=[32767],
            k_rows=[[0], [32767]],
            v_rows=[[256], [512]],
            row_index=1,
            causal=True,
        )
        score_low24 = ((32767 * 32767) >> 3) & 0xFFFFFF
        wrapped_score = score_low24 - (1 << 24) if score_low24 & 0x800000 else score_low24
        p = exp_pwl_u1_23(wrapped_score)
        self.assertEqual(0, state.m_s32_16)
        self.assertEqual((EXP_ONE_U1_23 + p) & 0xFFFFFFFF, state.l_u9_23)
        self.assertEqual(
            [(256 << 23) + (512 * p)],
            state.acc_s17_31,
        )

    def test_row_scoreboard_s4_det_matches_published_intermediate_checkpoints(self) -> None:
        lane_values = {
            0: [0x0100, 0x0200, -0x0100, 0x0080],
            1: [-0x0100, 0x0000, 0x0100, 0x0200],
            2: [0x0080, -0x0080, 0x0180, -0x0200],
            7: [0x0040, 0x0100, 0x0000, -0x0100],
            31: [-0x0200, -0x0100, 0x0080, 0x0400],
            63: [0x0200, -0x0080, 0x0040, 0x0100],
        }
        v_rows = [[0] * 64 for _ in range(4)]
        for lane, values in lane_values.items():
            for row, value in enumerate(values):
                v_rows[row][lane] = value

        state = softmax_row_fixed(
            q_row=[0x0100] + [0] * 63,
            k_rows=[
                [0x0000] + [0] * 63,
                [-0x0400] + [0] * 63,
                [-0x1000] + [0] * 63,
                [-0x2000] + [0] * 63,
            ],
            v_rows=v_rows,
            row_index=3,
            causal=True,
        )
        self.assertEqual(0x000000000000, state.m_s32_16)
        self.assertEqual(0x00E14DA2, state.l_u9_23)
        self.assertEqual(0x00010B1F0280, state.acc_s17_31[0])
        self.assertEqual(-1778188032, state.acc_s17_31[1])
        self.assertEqual(-5294836352, state.acc_s17_31[31])
        self.assertEqual(0x0000DFDB6FC0, state.acc_s17_31[63])
        self.assertEqual(0x48B842A1, reciprocal_u1_31(state.l_u9_23))
        self.assertEqual(
            [304, -120, 53, 122, -359, 254],
            [state.output_q88[lane] for lane in (0, 1, 2, 7, 31, 63)],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
