#!/usr/bin/env python3
"""Unit tests for vector output comparison fixtures and CLI."""

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

from scripts.compare_vector_output import compare_vectors, load_dut_words
from scripts.dump_fixture_sv import build_fixture_include
from scripts.generate_test_vectors import pack_beat64


FIXTURE_DIR = REPO_ROOT / "test_vectors" / "generated" / "s4_d64_seed100"
CASE_NAME = "s4_d64_seed100"
METADATA_PATH = FIXTURE_DIR / f"{CASE_NAME}_metadata.json"
S4_INCLUDE_PATH = REPO_ROOT / "sim" / "include" / "s4_d64_seed100_vectors.svh"


class TestCompareVectorOutput(unittest.TestCase):
    def test_committed_s4_d64_fixture_files_exist_and_metadata_matches_contract(self) -> None:
        metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))

        self.assertEqual("test_vector_format_v1", metadata["format_version"])
        self.assertEqual(CASE_NAME, metadata["case_name"])
        self.assertEqual(100, metadata["seed"])
        self.assertEqual(4, metadata["sequence_length"])
        self.assertEqual(64, metadata["dimension"])
        self.assertEqual(4, metadata["output_rows"])
        self.assertEqual(128, metadata["stride_bytes"])
        self.assertTrue(metadata["causal"])

        for file_info in metadata["files"].values():
            path = FIXTURE_DIR / file_info["path"]
            self.assertTrue(path.exists(), path)

    def test_golden_self_compare_passes_with_zero_error(self) -> None:
        result = compare_vectors(
            metadata_path=METADATA_PATH,
            dut_hex_path=FIXTURE_DIR / f"{CASE_NAME}_O_golden.hex",
            dut_format="words16",
            require_mae=0.0,
            require_maxae=0.0,
        )

        self.assertTrue(result.passed)
        self.assertEqual(0.0, result.mae)
        self.assertEqual(0.0, result.maxae)
        self.assertEqual(0, result.max_lsb_error)
        self.assertIsNone(result.first_failure)

    def test_single_word_perturbation_reports_failure_location(self) -> None:
        golden_words = (FIXTURE_DIR / f"{CASE_NAME}_O_golden.hex").read_text(encoding="ascii").splitlines()
        with tempfile.TemporaryDirectory() as tmp_dir:
            dut_path = Path(tmp_dir) / "dut.hex"
            perturbed = list(golden_words)
            perturbed[7] = f"{(int(perturbed[7], 16) + 1) & 0xFFFF:04X}"
            dut_path.write_text("\n".join(perturbed) + "\n", encoding="ascii")

            result = compare_vectors(
                metadata_path=METADATA_PATH,
                dut_hex_path=dut_path,
                dut_format="words16",
                require_mae=0.0,
                require_maxae=0.0,
            )

        self.assertFalse(result.passed)
        self.assertEqual(1, result.max_lsb_error)
        self.assertIsNotNone(result.first_failure)
        assert result.first_failure is not None
        self.assertEqual(0, result.first_failure["row"])
        self.assertEqual(7, result.first_failure["col"])

    def test_beats64_dut_unpack_uses_little_endian_lanes_and_stride_padding(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            dut_path = Path(tmp_dir) / "dut_beats64.hex"
            dut_path.write_text(
                "\n".join(
                    [
                        pack_beat64([0x0100, -256, 1, -32768]),
                        "0000000000000000",
                    ]
                )
                + "\n",
                encoding="ascii",
            )

            words = load_dut_words(
                dut_path,
                dut_format="beats64",
                dimension=4,
                rows=1,
                beats_per_row=2,
            )

        self.assertEqual([256, -256, 1, -32768], words)

    def test_cli_exits_nonzero_when_thresholds_fail(self) -> None:
        golden_words = (FIXTURE_DIR / f"{CASE_NAME}_O_golden.hex").read_text(encoding="ascii").splitlines()
        with tempfile.TemporaryDirectory() as tmp_dir:
            dut_path = Path(tmp_dir) / "dut.hex"
            perturbed = list(golden_words)
            perturbed[0] = f"{(int(perturbed[0], 16) + 1) & 0xFFFF:04X}"
            dut_path.write_text("\n".join(perturbed) + "\n", encoding="ascii")
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(REPO_ROOT / "scripts" / "compare_vector_output.py"),
                    "--metadata",
                    str(METADATA_PATH),
                    "--dut-hex",
                    str(dut_path),
                    "--format",
                    "words16",
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
        self.assertIn("FAIL", result.stdout)
        self.assertIn("row=0 col=0", result.stdout)
        self.assertIn("expected=", result.stdout)
        self.assertIn("got=", result.stdout)

    def test_cli_writes_summary_json_for_metadata_located_golden(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            summary_path = Path(tmp_dir) / "summary.json"
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(REPO_ROOT / "scripts" / "compare_vector_output.py"),
                    "--metadata",
                    str(METADATA_PATH),
                    "--dut-hex",
                    str(FIXTURE_DIR / f"{CASE_NAME}_O_golden.hex"),
                    "--format",
                    "words16",
                    "--require-mae",
                    "0",
                    "--require-maxae",
                    "0",
                    "--dump-summary-json",
                    str(summary_path),
                ],
                check=False,
                text=True,
                capture_output=True,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertTrue(summary_path.exists())
            summary = json.loads(summary_path.read_text(encoding="utf-8"))

        self.assertTrue(summary["passed"])
        self.assertEqual("PASS", summary["status"])
        self.assertEqual(256, summary["elements"])
        self.assertEqual(0.0, summary["mae"])
        self.assertEqual(0.0, summary["maxae"])
        self.assertEqual(0, summary["max_lsb_error"])
        self.assertIsNone(summary["first_failure"])
        self.assertEqual("words16", summary["dut_format"])
        self.assertEqual(str(METADATA_PATH), summary["metadata_path"])
        self.assertEqual(str(FIXTURE_DIR / f"{CASE_NAME}_O_golden.hex"), summary["golden_hex_path"])
        self.assertEqual(str(FIXTURE_DIR / f"{CASE_NAME}_O_golden.hex"), summary["dut_hex_path"])
        self.assertEqual(0.0, summary["thresholds"]["require_mae"])
        self.assertEqual(0.0, summary["thresholds"]["require_maxae"])
        self.assertEqual(CASE_NAME, summary["case_name"])
        self.assertEqual(64, summary["dimension"])
        self.assertEqual(4, summary["output_rows"])
        self.assertEqual(16, summary["beats_per_row"])

    def test_golden_self_compare_passes_for_beats64_output_dump(self) -> None:
        result = compare_vectors(
            metadata_path=METADATA_PATH,
            dut_hex_path=FIXTURE_DIR / f"{CASE_NAME}_O_golden_beats64.hex",
            dut_format="beats64",
            require_mae=0.0,
            require_maxae=0.0,
        )

        self.assertTrue(result.passed)
        self.assertEqual(256, result.elements)
        self.assertEqual(0, result.max_lsb_error)
        self.assertIsNone(result.first_failure)

    def test_s4_sv_include_matches_metadata_and_beat_files(self) -> None:
        include_text = build_fixture_include(METADATA_PATH, repo_root=REPO_ROOT)
        metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
        q_beats = (FIXTURE_DIR / f"{CASE_NAME}_Q_beats64.hex").read_text(encoding="ascii").splitlines()
        o_beats = (FIXTURE_DIR / f"{CASE_NAME}_O_golden_beats64.hex").read_text(encoding="ascii").splitlines()

        self.assertIn("localparam int S4_D64_SEED100_SEQUENCE_LENGTH = 4;", include_text)
        self.assertIn("localparam int S4_D64_SEED100_DIMENSION = 64;", include_text)
        self.assertIn("localparam int S4_D64_SEED100_BEATS_PER_ROW = 16;", include_text)
        self.assertIn("localparam int S4_D64_SEED100_O_GOLDEN_BEATS = 64;", include_text)
        self.assertIn(
            'localparam string S4_D64_SEED100_Q_BEATS64_HEX = "test_vectors/generated/s4_d64_seed100/s4_d64_seed100_Q_beats64.hex";',
            include_text,
        )
        self.assertEqual(metadata["output_rows"] * metadata["beats_per_row"], len(o_beats))
        self.assertIn(f"64'h{q_beats[0]}", include_text)
        self.assertIn(f"64'h{o_beats[-1]}", include_text)

    def test_s4_sv_include_lane_order_matches_words16_golden(self) -> None:
        include_text = build_fixture_include(METADATA_PATH, repo_root=REPO_ROOT)
        o_words = (FIXTURE_DIR / f"{CASE_NAME}_O_golden.hex").read_text(encoding="ascii").splitlines()
        first_beat = (FIXTURE_DIR / f"{CASE_NAME}_O_golden_beats64.hex").read_text(encoding="ascii").splitlines()[0]

        self.assertEqual(f"{o_words[3]}{o_words[2]}{o_words[1]}{o_words[0]}", first_beat)
        self.assertIn("return beat[(lane * 16) +: 16];", include_text)

    def test_committed_s4_sv_include_is_regenerated_output(self) -> None:
        expected = build_fixture_include(METADATA_PATH, repo_root=REPO_ROOT)
        self.assertEqual(expected, S4_INCLUDE_PATH.read_text(encoding="ascii"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
