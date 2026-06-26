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
from scripts.generate_test_vectors import pack_beat64


FIXTURE_DIR = REPO_ROOT / "test_vectors" / "generated" / "s4_d64_seed100"
CASE_NAME = "s4_d64_seed100"
METADATA_PATH = FIXTURE_DIR / f"{CASE_NAME}_metadata.json"


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


if __name__ == "__main__":
    unittest.main(verbosity=2)
