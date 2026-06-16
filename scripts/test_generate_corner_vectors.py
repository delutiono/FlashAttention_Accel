#!/usr/bin/env python3
"""Smoke tests for corner vector generation."""

from __future__ import annotations

import importlib.util
import math
import re
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "generate_corner_vectors.py"


class CornerVectorGenerationTest(unittest.TestCase):
    def test_exp_lut_v02_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "exp_lut_v02" / "expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=exp_lut_v02",
            "purpose=bringup_exp_lut_v02_expected_points",
            "input_format=S*.16",
            "output_format=U1.23",
            "not_final_exp_implementation=1",
            "x_zero_s16_16_hex=000000",
            "y_zero_u1_23_hex=800000",
            "x_neg_half_s16_16_hex=FF8000",
            "y_neg_half_u1_23_hex=4DA2CC",
            "x_neg_one_s16_16_hex=FF0000",
            "y_neg_one_u1_23_hex=2F16AC",
            "x_neg_two_s16_16_hex=FE0000",
            "y_neg_two_u1_23_hex=1152AB",
            "x_neg_four_s16_16_hex=FC0000",
            "y_neg_four_u1_23_hex=02582B",
            "x_neg_sixteen_s16_16_hex=F00000",
            "y_neg_sixteen_u1_23_hex=000000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

    def test_causal_i0_vector_smoke_expected_file_constants(self) -> None:
        v_path = REPO_ROOT / "test_vectors" / "cases" / "causal_i0_V.hex"
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "causal_i0" / "expected.txt"
        text = expected_path.read_text(encoding="ascii")
        v_lines = v_path.read_text(encoding="ascii").splitlines()

        self.assertEqual(256 * 64, len(v_lines), str(v_path))

        def signed_q88(hex_word: str) -> int:
            value = int(hex_word, 16)
            return value - 0x10000 if value & 0x8000 else value

        lane_expected = {
            dim: signed_q88(v_lines[dim]) << 23
            for dim in range(64)
        }

        self.assertEqual(2147483648, lane_expected[0])
        self.assertEqual(-2147483648, lane_expected[1])
        self.assertEqual(1073741824, lane_expected[2])
        self.assertEqual(0, lane_expected[63])

        required_lines = [
            "case=causal_i0",
            "purpose=scheduler_score_v64_softmax_smoke_expected_after_k0",
            "source=test_vectors/cases/causal_i0_V.hex",
            "formula=acc[d]=signed_q88(V[0][d])<<23",
            "D=64",
            "acc_format=S17.31",
            "lane00_v_q88_hex=0100",
            "lane00_acc_s17_31_hex=000080000000",
            "lane01_v_q88_hex=FF00",
            "lane01_acc_s17_31_hex=FFFF80000000",
            "lane02_v_q88_hex=0080",
            "lane02_acc_s17_31_hex=000040000000",
            "lane63_v_q88_hex=0000",
            "lane63_acc_s17_31_hex=000000000000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_acc_s17_31_hex=[0-9A-F]{12}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_causal_i0_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "causal_i0" / "final_expected.txt"
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=causal_i0",
            "purpose=finalization_smoke_expected_l_acc64_to_recip_out_quant_o_q88",
            "source=test_vectors/cases/causal_i0_V.hex",
            "D=64",
            "l_format=U9.23",
            "acc_format=S17.31",
            "recip_format=U1.31",
            "o_format=S8.8",
            "l_u9_23_dec=8388608",
            "l_u9_23_hex=00800000",
            "recip_u1_31_dec=2147483648",
            "recip_u1_31_hex=80000000",
            "formula=O_q88[d]=V[0][d]",
            "lane00_o_q88_dec=256",
            "lane00_o_q88_hex=0100",
            "lane01_o_q88_dec=-256",
            "lane01_o_q88_hex=FF00",
            "lane02_o_q88_dec=128",
            "lane02_o_q88_hex=0080",
            "lane63_o_q88_dec=0",
            "lane63_o_q88_hex=0000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_causal_i0_pipeline_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "causal_i0" / "pipeline_final_expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=causal_i0",
            "purpose=scheduler_score_pipe_softmax_vec_finalize_vec_pipeline_final_e2e_smoke_expected",
            "path=scheduler -> score_pipe -> softmax_vec -> finalize_vec",
            "source_score=test_vectors/debug/causal_i0/score_tile.hex",
            "source_mask=test_vectors/debug/causal_i0/mask_valid.hex",
            "source_softmax=test_vectors/debug/causal_i0/expected.txt",
            "source_final=test_vectors/debug/causal_i0/final_expected.txt",
            "D=64",
            "lane_count=64",
            "not_full_s256_random_golden=1",
            "q0_k0_q88_rule=Q0_and_K0_all_zero",
            "q0_k0_score_scaled_s32_16_hex=000000000000",
            "q0_k1_masked_valid=0",
            "q0_k1_masked_rule=no_update",
            "q0_k1_masked_score_scaled_s32_16_hex=000000000000",
            "softmax_final_m_s32_16_hex=000000000000",
            "softmax_final_l_u9_23_hex=00800000",
            "softmax_final_acc_formula=acc[d]=signed_q88(V[0][d])<<23",
            "final_recip_u1_31_hex=80000000",
            "final_formula=O_q88[d]=V[0][d]",
            "lane00_v_q88_hex=0100",
            "lane00_acc_s17_31_hex=000080000000",
            "lane00_o_q88_hex=0100",
            "lane01_v_q88_hex=FF00",
            "lane01_acc_s17_31_hex=FFFF80000000",
            "lane01_o_q88_hex=FF00",
            "lane02_v_q88_hex=0080",
            "lane02_acc_s17_31_hex=000040000000",
            "lane02_o_q88_hex=0080",
            "lane63_v_q88_hex=0000",
            "lane63_acc_s17_31_hex=000000000000",
            "lane63_o_q88_hex=0000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_q1_equal_two_valid_pipeline_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "q1_equal_two_valid" / "pipeline_final_expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=q1_equal_two_valid",
            "purpose=scheduler_score_pipe_softmax_vec_finalize_vec_pipeline_final_q1_two_valid_smoke_expected",
            "path=scheduler -> score_pipe -> softmax_vec -> finalize_vec",
            "D=64",
            "q_index=01",
            "lane_count=64",
            "not_random_row_level_golden=1",
            "not_full_s256_random_golden=1",
            "q1_k0_valid=1",
            "q1_k0_score_scaled_s32_16_hex=000000000000",
            "q1_k1_valid=1",
            "q1_k1_score_scaled_s32_16_hex=000000000000",
            "q1_k2_masked_valid=0",
            "q1_k2_masked_rule=no_update",
            "q1_k2_masked_score_scaled_s32_16_hex=000000000000",
            "softmax_after_k0_l_u9_23_hex=00800000",
            "softmax_after_k1_l_u9_23_hex=01000000",
            "softmax_final_l_u9_23_hex=01000000",
            "final_recip_u1_31_hex=40000000",
            "final_formula=O_q88[d]=(V0[d]+V1[d])/2",
            "final_summary=O=(V0+V1)/2",
            "lane00_o_q88_hex=00C0",
            "lane01_o_q88_hex=0000",
            "lane63_o_q88_hex=0080",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_q1_delta_neg1_pipeline_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "q1_delta_neg1" / "pipeline_final_expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=q1_delta_neg1",
            "purpose=scheduler_score_pipe_softmax_vec_finalize_vec_pipeline_final_q1_delta_neg1_smoke_expected",
            "path=scheduler -> score_pipe -> softmax_vec -> finalize_vec",
            "D=64",
            "q_index=01",
            "lane_count=64",
            "controlled_qkv_rule=Q1[0]=0100,K0[0]=0000,K1[0]=F800,others_zero,K2_masked",
            "q1_k0_valid=1",
            "q1_k0_score_scaled_s32_16_hex=000000000000",
            "q1_k0_softmax_score_low24_hex=000000",
            "q1_k1_valid=1",
            "q1_k1_score_raw_s32_16_dec=-524288",
            "q1_k1_score_scaled_s32_16_dec=-65536",
            "q1_k1_score_scaled_s32_16_hex=FFFFFFFF0000",
            "q1_k1_softmax_score_low24_hex=FF0000",
            "q1_k2_masked_valid=0",
            "q1_k2_masked_rule=no_update",
            "exp_neg1_u1_23_hex=002F16AC",
            "softmax_after_k0_l_u9_23_hex=00800000",
            "softmax_after_k1_l_u9_23_hex=00AF16AC",
            "softmax_final_l_u9_23_hex=00AF16AC",
            "softmax_final_acc_dim00_s17_31_hex=0000DE2D5800",
            "final_recip_u1_31_hex=5D935411",
            "lane00_v0_q88_hex=0100",
            "lane00_v1_q88_hex=0200",
            "lane00_o_q88_hex=0145",
            "lane01_o_q88_hex=0000",
            "lane63_o_q88_hex=0000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_q1_delta_neg_half_pipeline_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "q1_delta_neg_half" / "pipeline_final_expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=q1_delta_neg_half",
            "purpose=scheduler_score_pipe_softmax_vec_finalize_vec_pipeline_final_q1_delta_neg_half_smoke_expected",
            "path=scheduler -> score_pipe -> softmax_vec -> finalize_vec",
            "D=64",
            "q_index=01",
            "lane_count=64",
            "controlled_qkv_rule=Q1[0]=0100,K0[0]=0000,K1[0]=FC00,others_zero,K2_masked",
            "not_random_row_level_golden=1",
            "not_full_s256_random_golden=1",
            "not_final_exp_recip_random_golden=1",
            "q1_k0_valid=1",
            "q1_k0_score_scaled_s32_16_hex=000000000000",
            "q1_k0_softmax_score_low24_hex=000000",
            "q1_k1_valid=1",
            "q1_k1_score_raw_s32_16_dec=-262144",
            "q1_k1_score_scaled_s32_16_dec=-32768",
            "q1_k1_score_scaled_s32_16_hex=FFFFFFFF8000",
            "q1_k1_softmax_score_low24_hex=FF8000",
            "q1_k2_masked_valid=0",
            "q1_k2_masked_rule=no_update",
            "q1_k2_masked_score_scaled_s32_16_hex=000000000000",
            "exp_neg_half_u1_23_hex=004DA2CC",
            "softmax_after_k0_l_u9_23_hex=00800000",
            "softmax_after_k1_l_u9_23_hex=00CDA2CC",
            "softmax_final_l_u9_23_hex=00CDA2CC",
            "softmax_final_acc_dim00_s17_31_hex=00011B459800",
            "final_recip_u1_31_hex=4FACBF4E",
            "lane00_v0_q88_hex=0100",
            "lane00_v1_q88_hex=0200",
            "lane00_o_q88_hex=0161",
            "lane01_o_q88_hex=0000",
            "lane63_o_q88_hex=0000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_q1_delta_neg2_pipeline_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "q1_delta_neg2" / "pipeline_final_expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=q1_delta_neg2",
            "purpose=scheduler_score_pipe_softmax_vec_finalize_vec_pipeline_final_q1_delta_neg2_smoke_expected",
            "path=scheduler -> score_pipe -> softmax_vec -> finalize_vec",
            "D=64",
            "q_index=01",
            "lane_count=64",
            "controlled_qkv_rule=Q1[0]=0100,K0[0]=0000,K1[0]=F000,others_zero,K2_masked",
            "not_random_row_level_golden=1",
            "not_full_s256_random_golden=1",
            "not_final_exp_recip_random_golden=1",
            "q1_k0_valid=1",
            "q1_k0_score_scaled_s32_16_hex=000000000000",
            "q1_k0_softmax_score_low24_hex=000000",
            "q1_k1_valid=1",
            "q1_k1_score_raw_s32_16_dec=-1048576",
            "q1_k1_score_scaled_s32_16_dec=-131072",
            "q1_k1_score_scaled_s32_16_hex=FFFFFFFE0000",
            "q1_k1_softmax_score_low24_hex=FE0000",
            "q1_k2_masked_valid=0",
            "q1_k2_masked_rule=no_update",
            "q1_k2_masked_score_scaled_s32_16_hex=000000000000",
            "exp_neg2_u1_23_hex=001152AB",
            "softmax_after_k0_l_u9_23_hex=00800000",
            "softmax_after_k1_l_u9_23_hex=009152AB",
            "softmax_final_l_u9_23_hex=009152AB",
            "softmax_final_acc_dim00_s17_31_hex=0000A2A55600",
            "final_recip_u1_31_hex=70BDF523",
            "lane00_v0_q88_hex=0100",
            "lane00_v1_q88_hex=0200",
            "lane00_o_q88_hex=011F",
            "lane01_o_q88_hex=0000",
            "lane63_o_q88_hex=0000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_q1_delta_neg4_pipeline_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "q1_delta_neg4" / "pipeline_final_expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=q1_delta_neg4",
            "purpose=scheduler_score_pipe_softmax_vec_finalize_vec_pipeline_final_q1_delta_neg4_smoke_expected",
            "path=scheduler -> score_pipe -> softmax_vec -> finalize_vec",
            "D=64",
            "q_index=01",
            "lane_count=64",
            "controlled_qkv_rule=Q1[0]=0100,K0[0]=0000,K1[0]=E000,others_zero,K2_masked",
            "not_random_row_level_golden=1",
            "not_full_s256_random_golden=1",
            "not_final_exp_recip_random_golden=1",
            "q1_k0_valid=1",
            "q1_k0_score_scaled_s32_16_hex=000000000000",
            "q1_k0_softmax_score_low24_hex=000000",
            "q1_k1_valid=1",
            "q1_k1_score_raw_s32_16_dec=-2097152",
            "q1_k1_score_scaled_s32_16_dec=-262144",
            "q1_k1_score_scaled_s32_16_hex=FFFFFFFC0000",
            "q1_k1_softmax_score_low24_hex=FC0000",
            "q1_k2_masked_valid=0",
            "q1_k2_masked_rule=no_update",
            "q1_k2_masked_score_scaled_s32_16_hex=000000000000",
            "exp_neg4_u1_23_hex=0002582B",
            "softmax_after_k0_l_u9_23_hex=00800000",
            "softmax_after_k1_l_u9_23_hex=0082582B",
            "softmax_final_l_u9_23_hex=0082582B",
            "softmax_final_acc_dim00_s17_31_hex=000084B05600",
            "final_recip_u1_31_hex=7DB2A076",
            "lane00_v0_q88_hex=0100",
            "lane00_v1_q88_hex=0200",
            "lane00_o_q88_hex=0105",
            "lane01_o_q88_hex=0000",
            "lane63_o_q88_hex=0000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_row_scoreboard_s4_det_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "row_scoreboard_s4_det" / "expected.txt"
        q_path = REPO_ROOT / "test_vectors" / "cases" / "row_scoreboard_s4_det_Q.hex"
        k_path = REPO_ROOT / "test_vectors" / "cases" / "row_scoreboard_s4_det_K.hex"
        v_path = REPO_ROOT / "test_vectors" / "cases" / "row_scoreboard_s4_det_V.hex"
        self.assertTrue(expected_path.exists(), str(expected_path))
        for path in (q_path, k_path, v_path):
            self.assertTrue(path.exists(), str(path))
        text = expected_path.read_text(encoding="ascii")
        q_lines = q_path.read_text(encoding="ascii").splitlines()
        k_lines = k_path.read_text(encoding="ascii").splitlines()
        v_lines = v_path.read_text(encoding="ascii").splitlines()

        for path, lines in ((q_path, q_lines), (k_path, k_lines), (v_path, v_lines)):
            self.assertEqual(256 * 64, len(lines), str(path))
            self.assertTrue(all(re.fullmatch(r"[0-9A-F]{4}", line) for line in lines), str(path))

        def word(lines: list[str], row: int, lane: int) -> str:
            return lines[row * 64 + lane]

        self.assertEqual("0100", word(q_lines, 3, 0))
        for index, value in enumerate(q_lines):
            if index != 3 * 64:
                self.assertEqual("0000", value, f"{q_path}:{index}")

        expected_k = {
            (0, 0): "0000",
            (1, 0): "FC00",
            (2, 0): "F000",
            (3, 0): "E000",
        }
        for (row, lane), value in expected_k.items():
            self.assertEqual(value, word(k_lines, row, lane))
        for index, value in enumerate(k_lines):
            row, lane = divmod(index, 64)
            if (row, lane) not in expected_k:
                self.assertEqual("0000", value, f"{k_path}:{index}")

        checked_lanes = (0, 1, 2, 7, 31, 63)
        expected_v = {}
        for row in range(4):
            for lane in checked_lanes:
                match = re.search(rf"^lane{lane:02d}_v{row}_q88_hex=([0-9A-F]{{4}})$", text, re.MULTILINE)
                self.assertIsNotNone(match, f"lane{lane:02d}_v{row}_q88_hex")
                expected_v[(row, lane)] = match.group(1)

        for (row, lane), value in expected_v.items():
            self.assertEqual(value, word(v_lines, row, lane))
        for index, value in enumerate(v_lines):
            row, lane = divmod(index, 64)
            if (row, lane) not in expected_v:
                self.assertEqual("0000", value, f"{v_path}:{index}")

        required_lines = [
            "case=row_scoreboard_s4_det",
            "purpose=row_level_scoreboard_s4_d64_deterministic_expected",
            "scope=deterministic_row_level_scoreboard_expected",
            "S_active=4",
            "D=64",
            "q_index=03",
            "active_k_count=4",
            "lane_count=64",
            "not_full_s256_random_golden=1",
            "not_final_exp_recip_contract=1",
            "score_sequence_s32_16_hex=000000000000,FFFFFFFF8000,FFFFFFFE0000,FFFFFFFC0000",
            "exp_sequence_u1_23_hex=00800000,004DA2CC,001152AB,0002582B",
            "softmax_final_l_u9_23_hex=00E14DA2",
            "final_recip_u1_31_hex=48B842A1",
            "lane00_acc_s17_31_hex=00010B1F0280",
            "lane00_o_q88_hex=0130",
            "lane01_acc_s17_31_hex=FFFF96030100",
            "lane01_o_q88_hex=FF88",
            "lane02_acc_s17_31_hex=00002E7A4480",
            "lane02_o_q88_hex=0035",
            "lane07_acc_s17_31_hex=00006B4AA100",
            "lane07_o_q88_hex=007A",
            "lane31_acc_s17_31_hex=FFFEC4673580",
            "lane31_o_q88_hex=FE99",
            "lane63_acc_s17_31_hex=0000DFDB6FC0",
            "lane63_o_q88_hex=00FE",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_softmax_vec_first_equal_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "softmax_vec_first_equal" / "expected.txt"
        text = expected_path.read_text(encoding="ascii")

        exp0 = 1 << 23
        v0_lane0_q88 = 0x0100
        v0_lane1_q88 = -0x0100
        v0_lane63_q88 = 0x0200
        v1_lane0_q88 = 0x0080
        v1_lane1_q88 = 0x0100
        v1_lane63_q88 = -0x0100

        first_lane0 = v0_lane0_q88 * exp0
        first_lane1 = v0_lane1_q88 * exp0
        first_lane63 = v0_lane63_q88 * exp0
        delta_lane0 = v1_lane0_q88 * exp0
        delta_lane1 = v1_lane1_q88 * exp0
        delta_lane63 = v1_lane63_q88 * exp0
        after_lane0 = first_lane0 + delta_lane0
        after_lane1 = first_lane1 + delta_lane1
        after_lane63 = first_lane63 + delta_lane63

        self.assertEqual(2147483648, first_lane0)
        self.assertEqual(-2147483648, first_lane1)
        self.assertEqual(4294967296, first_lane63)
        self.assertEqual(1073741824, delta_lane0)
        self.assertEqual(2147483648, delta_lane1)
        self.assertEqual(-2147483648, delta_lane63)
        self.assertEqual(3221225472, after_lane0)
        self.assertEqual(0, after_lane1)
        self.assertEqual(2147483648, after_lane63)

        required_lines = [
            "case=softmax_vec_first_equal",
            "D=64",
            "acc_format=S17.31",
            "m_l_scope=shared_per_query_row",
            "acc_scope=independent_per_lane",
            "first_valid_l_u9_23_hex=00800000",
            "equal_score_l_new_u9_23_hex=01000000",
            "first_valid_acc_dim00_s17_31_hex=000080000000",
            "first_valid_acc_dim01_s17_31_hex=FFFF80000000",
            "first_valid_acc_dim63_s17_31_hex=000100000000",
            "equal_score_acc_delta_dim00_s17_31_hex=000040000000",
            "equal_score_acc_delta_dim01_s17_31_hex=000080000000",
            "equal_score_acc_delta_dim63_s17_31_hex=FFFF80000000",
            "equal_score_acc_new_dim00_s17_31_hex=0000C0000000",
            "equal_score_acc_new_dim01_s17_31_hex=000000000000",
            "equal_score_acc_new_dim63_s17_31_hex=000080000000",
        ]
        for line in required_lines:
            self.assertIn(line, text)

    def test_softmax_vec_first_equal_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "softmax_vec_first_equal" / "final_expected.txt"
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=softmax_vec_first_equal",
            "purpose=finalization_smoke_expected_equal_score_l2_acc64_to_recip_out_quant_o_q88",
            "source=test_vectors/debug/softmax_vec_first_equal/expected.txt",
            "D=64",
            "l_format=U9.23",
            "acc_format=S17.31",
            "recip_format=U1.31",
            "o_format=S8.8",
            "rounding_tie_rule=half_away_from_zero",
            "l_u9_23_dec=16777216",
            "l_u9_23_hex=01000000",
            "recip_u1_31_dec=1073741824",
            "recip_u1_31_hex=40000000",
            "lane00_acc_s17_31_hex=0000C0000000",
            "lane00_o_q88_dec=192",
            "lane00_o_q88_hex=00C0",
            "lane01_acc_s17_31_hex=000000000000",
            "lane01_o_q88_dec=0",
            "lane01_o_q88_hex=0000",
            "lane63_acc_s17_31_hex=000080000000",
            "lane63_o_q88_dec=128",
            "lane63_o_q88_hex=0080",
        ]
        for line in required_lines:
            self.assertIn(line, text)

        lane_lines = [
            line for line in text.splitlines()
            if re.fullmatch(r"lane(?:[0-5][0-9]|6[0-3])_o_q88_hex=[0-9A-F]{4}", line)
        ]
        self.assertEqual(64, len(lane_lines), str(expected_path))

    def test_softmax_vec_first_equal_pipeline_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "softmax_vec_first_equal" / "pipeline_expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        required_lines = [
            "case=softmax_vec_first_equal",
            "purpose=softmax_vec_to_finalize_vec_pipeline_e2e_smoke_expected",
            "source_softmax=test_vectors/debug/softmax_vec_first_equal/expected.txt",
            "source_final=test_vectors/debug/softmax_vec_first_equal/final_expected.txt",
            "D=64",
            "lane_count=64",
            "unspecified_lane_default_o_q88_hex=0000",
            "input_beat0_score_s32_16_hex=000000000000",
            "input_beat0_v_tag=V0",
            "input_beat1_score_s32_16_hex=000000000000",
            "input_beat1_v_tag=V2",
            "softmax_final_m_s32_16_hex=000000000000",
            "softmax_final_l_u9_23_hex=01000000",
            "softmax_final_acc_formula=(V0_q88[d]+V2_q88[d])<<23",
            "final_recip_u1_31_hex=40000000",
            "lane00_o_q88_hex=00C0",
            "lane01_o_q88_hex=0000",
            "lane63_o_q88_hex=0080",
        ]
        for line in required_lines:
            self.assertIn(line, text)

    def test_softmax_lower_by_one_final_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "softmax_lower_by_one" / "final_expected.txt"
        text = expected_path.read_text(encoding="ascii")

        l_u9_23 = 0x00AF16AC
        recip = ((1 << 31) * (1 << 23) + (l_u9_23 // 2)) // l_u9_23
        self.assertEqual(1569936401, recip)
        self.assertEqual("5D935411", f"{recip:08X}")

        required_lines = [
            "case=softmax_lower_by_one",
            "purpose=finalization_smoke_expected_l_expneg1_single_lane_to_recip_out_quant_o_q88",
            "source=test_vectors/debug/softmax_lower_by_one/expected.txt",
            "D=1",
            "l_format=U9.23",
            "acc_format=S17.31",
            "recip_format=U1.31",
            "o_format=S8.8",
            "rounding_tie_rule=half_away_from_zero",
            "l_u9_23_dec=11474604",
            "l_u9_23_hex=00AF16AC",
            "recip_formula=round((2^31*2^23)/l_u9_23)",
            "recip_u1_31_dec=1569936401",
            "recip_u1_31_hex=5D935411",
            "lane00_acc_s17_31_dec=3727513600",
            "lane00_acc_s17_31_hex=0000DE2D5800",
            "lane00_o_q88_dec=325",
            "lane00_o_q88_hex=0145",
        ]
        for line in required_lines:
            self.assertIn(line, text)

    def test_softmax_raise_by_one_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "softmax_raise_by_one" / "expected.txt"
        text = expected_path.read_text(encoding="ascii")

        exp0 = 1 << 23
        alpha = round(math.exp(-1.0) * (1 << 23))
        v0_q88 = 0x0100
        v1_q88 = 0x0200
        old_acc_rescaled = (v0_q88 * exp0 * alpha) >> 23
        new_acc_contrib = v1_q88 * exp0
        acc_new = old_acc_rescaled + new_acc_contrib

        self.assertEqual(3085996, alpha)
        self.assertEqual("002F16AC", f"{alpha:08X}")
        self.assertEqual(11474604, ((exp0 * alpha) >> 23) + exp0)
        self.assertEqual("00AF16AC", f"{(((exp0 * alpha) >> 23) + exp0):08X}")
        self.assertEqual(790014976, old_acc_rescaled)
        self.assertEqual("00002F16AC00", f"{old_acc_rescaled:012X}")
        self.assertEqual(4294967296, new_acc_contrib)
        self.assertEqual("000100000000", f"{new_acc_contrib:012X}")
        self.assertEqual(5084982272, acc_new)
        self.assertEqual("00012F16AC00", f"{acc_new:012X}")

        required_lines = [
            "case=softmax_raise_by_one",
            "second_score_s32_16_hex=000000010000",
            "alpha_exp_neg1_u1_23_hex=002F16AC",
            "p_exp0_u1_23_hex=00800000",
            "l_new_u9_23_hex=00AF16AC",
            "acc_old_rescaled_s17_31_hex=00002F16AC00",
            "acc_new_contrib_v1_times_p_s17_31_hex=000100000000",
            "acc_new_s17_31_hex=00012F16AC00",
        ]
        for line in required_lines:
            self.assertIn(line, text)

    def test_softmax_lower_by_one_bringup_constants(self) -> None:
        exp0 = 1 << 23
        exp_neg1 = round(math.exp(-1.0) * (1 << 23))
        v0_q88 = 0x0100
        v1_q88 = 0x0200
        acc_old = v0_q88 * exp0
        acc_delta = v1_q88 * exp_neg1
        acc_new = acc_old + acc_delta

        self.assertEqual(8388608, exp0)
        self.assertEqual(3085996, exp_neg1)
        self.assertEqual("00800000", f"{exp0:08X}")
        self.assertEqual("002F16AC", f"{exp_neg1:08X}")
        self.assertEqual(11474604, exp0 + exp_neg1)
        self.assertEqual("00AF16AC", f"{exp0 + exp_neg1:08X}")
        self.assertEqual(2147483648, acc_old)
        self.assertEqual(1580029952, acc_delta)
        self.assertEqual(3727513600, acc_new)
        self.assertEqual("000080000000", f"{acc_old:012X}")
        self.assertEqual("00005E2D5800", f"{acc_delta:012X}")
        self.assertEqual("0000DE2D5800", f"{acc_new:012X}")

    def test_softmax_lower_by_half_expected_file_constants(self) -> None:
        expected_path = REPO_ROOT / "test_vectors" / "debug" / "softmax_lower_by_half" / "expected.txt"
        self.assertTrue(expected_path.exists(), str(expected_path))
        text = expected_path.read_text(encoding="ascii")

        exp0 = 1 << 23
        p = 0x004DA2CC
        v0_q88 = 0x0100
        v1_q88 = 0x0200
        acc_old = v0_q88 * exp0
        acc_delta = v1_q88 * p
        acc_new = acc_old + acc_delta
        l_new = exp0 + p

        self.assertEqual(5087948, p)
        self.assertEqual(13476556, l_new)
        self.assertEqual(2147483648, acc_old)
        self.assertEqual(2605029376, acc_delta)
        self.assertEqual(4752513024, acc_new)
        self.assertEqual("004DA2CC", f"{p:08X}")
        self.assertEqual("00CDA2CC", f"{l_new:08X}")
        self.assertEqual("000080000000", f"{acc_old:012X}")
        self.assertEqual("00009B459800", f"{acc_delta:012X}")
        self.assertEqual("00011B459800", f"{acc_new:012X}")

        required_lines = [
            "case=softmax_lower_by_half",
            "purpose=softmax_generic_lower_delta_v02_smoke_expected",
            "not_final_exp_lut_or_pwl=1",
            "not_row_level_golden=1",
            "first_score_s32_16_hex=000000000000",
            "second_score_s32_16_hex=FFFFFFFF8000",
            "p=004DA2CC",
            "p_dec=5087948",
            "p_exp_neg_half_u1_23_dec=5087948",
            "p_exp_neg_half_u1_23_hex=004DA2CC",
            "l_new_formula=(1<<23)+p",
            "l_new_u9_23_dec=13476556",
            "l_new_u9_23_hex=00CDA2CC",
            "acc_new_formula=(1.0<<23)+(2.0*p)",
            "acc_new_s17_31_dec=4752513024",
            "acc_new_s17_31_hex=00011B459800",
        ]
        for line in required_lines:
            self.assertIn(line, text)

    def test_generates_baseline_corner_cases_with_valid_hex_files(self) -> None:
        spec = importlib.util.spec_from_file_location("generate_corner_vectors", SCRIPT_PATH)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with tempfile.TemporaryDirectory() as tmpdir:
            generated = module.generate_all(Path(tmpdir))

            self.assertEqual(
                {"zero", "causal_i0", "causal_i255", "tile_boundary", "non_causal_smoke"},
                set(generated),
            )
            for case_name in generated:
                for tensor in ("Q", "K", "V", "O_ref", "O_q88"):
                    path = Path(tmpdir) / f"{case_name}_{tensor}.hex"
                    self.assertTrue(path.exists(), str(path))
                    lines = path.read_text(encoding="ascii").splitlines()
                    self.assertEqual(256 * 64, len(lines), str(path))
                    self.assertTrue(all(re.fullmatch(r"[0-9A-F]{4}", line) for line in lines), str(path))

            debug_dir = Path(tmpdir) / ".." / "debug" / "causal_i0"
            meta_path = debug_dir / "meta.txt"
            score_path = debug_dir / "score_tile.hex"
            mask_path = debug_dir / "mask_valid.hex"
            ml_path = debug_dir / "m_l_after_tile.hex"
            self.assertTrue(meta_path.exists(), str(meta_path))
            self.assertTrue(score_path.exists(), str(score_path))
            self.assertTrue(mask_path.exists(), str(mask_path))
            self.assertTrue(ml_path.exists(), str(ml_path))
            meta_text = meta_path.read_text(encoding="ascii")
            self.assertIn("case=causal_i0", meta_text)
            self.assertIn("subset=q_index=00 only", meta_text)
            self.assertIn("first_valid_l=00800000", meta_text)
            self.assertIn("pipeline_scalar_dim=00", meta_text)
            self.assertIn("expected_after_k0_score=000000000000", meta_text)
            self.assertIn("expected_after_k0_m=000000000000", meta_text)
            self.assertIn("expected_after_k0_l=00800000", meta_text)
            self.assertIn("expected_after_k0_acc_dim00=000080000000", meta_text)
            self.assertIn("expected_after_k1_masked_valid=0", meta_text)
            self.assertIn("expected_after_k1_masked_score=000000000000", meta_text)
            self.assertIn("expected_after_k1_masked_m=000000000000", meta_text)
            self.assertIn("expected_after_k1_masked_l=00800000", meta_text)
            self.assertIn("expected_after_k1_masked_acc_dim00=000080000000", meta_text)
            self.assertIn("expected_after_k1_masked_rule=no_update_from_after_k0", meta_text)

            score_lines = score_path.read_text(encoding="ascii").splitlines()
            self.assertEqual(256, len(score_lines), str(score_path))
            self.assertTrue(
                all(re.fullmatch(r"00 [0-7][0-9A-F] [0-9A-F]{2} [0-9A-F]{12}", line) for line in score_lines),
                str(score_path),
            )

            mask_lines = mask_path.read_text(encoding="ascii").splitlines()
            self.assertEqual(256, len(mask_lines), str(mask_path))
            self.assertTrue(all(re.fullmatch(r"00 [0-7][0-9A-F] [0-9A-F]{2} [01]", line) for line in mask_lines), str(mask_path))
            self.assertEqual(1, sum(line.endswith(" 1") for line in mask_lines), str(mask_path))

            ml_lines = ml_path.read_text(encoding="ascii").splitlines()
            self.assertEqual(8, len(ml_lines), str(ml_path))
            self.assertTrue(all(re.fullmatch(r"00 [0-7][0-9A-F] [0-9A-F]{12} [0-9A-F]{8}", line) for line in ml_lines))
            self.assertEqual("00 00 000000000000 00800000", ml_lines[0])

            non_causal_debug_dir = Path(tmpdir) / ".." / "debug" / "non_causal_smoke"
            non_causal_meta_path = non_causal_debug_dir / "meta.txt"
            non_causal_acc_path = non_causal_debug_dir / "acc_after_tile.hex"
            self.assertTrue(non_causal_meta_path.exists(), str(non_causal_meta_path))
            self.assertTrue(non_causal_acc_path.exists(), str(non_causal_acc_path))

            non_causal_meta = non_causal_meta_path.read_text(encoding="ascii")
            self.assertIn("case=non_causal_smoke", non_causal_meta)
            self.assertIn("subset=q_index=00 first_tile only", non_causal_meta)
            self.assertIn("equal_score_assumption=k01_and_k02_score_equal_m_after_k01", non_causal_meta)
            self.assertIn("second_equal_score_p=00800000", non_causal_meta)
            self.assertIn("second_equal_score_alpha=00800000", non_causal_meta)
            self.assertIn("second_equal_score_l_delta=00800000", non_causal_meta)

            acc_lines = non_causal_acc_path.read_text(encoding="ascii").splitlines()
            self.assertEqual(64, len(acc_lines), str(non_causal_acc_path))
            self.assertTrue(
                all(re.fullmatch(r"00 00 [0-3][0-9A-F] [0-9A-F]{12}", line) for line in acc_lines),
                str(non_causal_acc_path),
            )


if __name__ == "__main__":
    unittest.main()
