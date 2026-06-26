#!/usr/bin/env python3
"""Unit tests for deterministic RTL-friendly vector export."""

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

from scripts.generate_test_vectors import export_case, int16_hex, pack_beat64
from scripts.run_numeric_regression import generate_qkv
from model.golden_fixed import attention_fixed


class TestVectorGeneration(unittest.TestCase):
    def test_int16_hex_uses_twos_complement_uppercase_words(self) -> None:
        self.assertEqual("0000", int16_hex(0))
        self.assertEqual("0100", int16_hex(256))
        self.assertEqual("FF00", int16_hex(-256))
        self.assertEqual("8000", int16_hex(-32768))
        self.assertEqual("7FFF", int16_hex(32767))

    def test_pack_beat64_uses_little_endian_int16_lanes(self) -> None:
        self.assertEqual(
            "80000001FF000100",
            pack_beat64([0x0100, -256, 1, -32768]),
        )

    def test_export_small_case_is_reproducible_and_matches_fixed_golden(self) -> None:
        with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
            first = export_case(
                seed=7,
                sequence_length=8,
                dimension=8,
                max_rows=3,
                case_name="smoke_s8_d8_seed7",
                output_dir=Path(first_dir),
            )
            second = export_case(
                seed=7,
                sequence_length=8,
                dimension=8,
                max_rows=3,
                case_name="smoke_s8_d8_seed7",
                output_dir=Path(second_dir),
            )

            first_files = sorted(path.name for path in Path(first_dir).iterdir())
            second_files = sorted(path.name for path in Path(second_dir).iterdir())
            self.assertEqual(first_files, second_files)
            for file_name in first_files:
                self.assertEqual(
                    (Path(first_dir) / file_name).read_text(encoding="ascii"),
                    (Path(second_dir) / file_name).read_text(encoding="ascii"),
                    file_name,
                )

            q_rows, k_rows, v_rows = generate_qkv(7, 8, 8)
            expected_o = attention_fixed(q_rows, k_rows, v_rows, max_rows=3)
            q_words = (Path(first_dir) / "smoke_s8_d8_seed7_Q.hex").read_text(encoding="ascii").splitlines()
            k_words = (Path(first_dir) / "smoke_s8_d8_seed7_K.hex").read_text(encoding="ascii").splitlines()
            v_words = (Path(first_dir) / "smoke_s8_d8_seed7_V.hex").read_text(encoding="ascii").splitlines()
            o_words = (Path(first_dir) / "smoke_s8_d8_seed7_O_golden.hex").read_text(encoding="ascii").splitlines()
            self.assertEqual([int16_hex(value) for row in q_rows for value in row], q_words)
            self.assertEqual([int16_hex(value) for row in k_rows for value in row], k_words)
            self.assertEqual([int16_hex(value) for row in v_rows for value in row], v_words)
            self.assertEqual([int16_hex(value) for row in expected_o for value in row], o_words)
            self.assertEqual(8 * 8, len(q_words))
            self.assertEqual(3 * 8, len(o_words))
            self.assertEqual(first["files"]["O_golden_16b_hex"]["elements"], 24)

    def test_export_writes_metadata_and_64bit_beat_files_with_stride_padding(self) -> None:
        with tempfile.TemporaryDirectory() as output_dir:
            metadata = export_case(
                seed=11,
                sequence_length=8,
                dimension=8,
                max_rows=2,
                case_name="smoke",
                output_dir=Path(output_dir),
                stride_bytes=128,
            )
            metadata_path = Path(output_dir) / "smoke_metadata.json"
            payload = json.loads(metadata_path.read_text(encoding="utf-8"))
            self.assertEqual(metadata, payload)
            self.assertEqual("test_vector_format_v1", payload["format_version"])
            self.assertEqual("row_major", payload["layout"])
            self.assertEqual("little-endian bytes; WDATA[15:0] is lowest-column int16", payload["beat64_endian"])
            self.assertEqual(128, payload["stride_bytes"])
            self.assertEqual(16, payload["beats_per_row"])
            self.assertEqual(8, payload["dimension"])
            self.assertEqual(2, payload["output_rows"])
            self.assertEqual("Q8.8 signed int16", payload["numeric_format"])
            self.assertEqual(
                {"mode": "nr", "lut_entries": 32, "nr_iterations": 1, "valid_latency": 4},
                payload["reciprocal"],
            )

            q_words = (Path(output_dir) / "smoke_Q.hex").read_text(encoding="ascii").splitlines()
            q_beats = (Path(output_dir) / "smoke_Q_beats64.hex").read_text(encoding="ascii").splitlines()
            self.assertEqual(8 * 16, len(q_beats))
            self.assertEqual(pack_beat64([int(word, 16) for word in q_words[:4]]), q_beats[0])
            self.assertEqual(pack_beat64([int(word, 16) for word in q_words[4:8]]), q_beats[1])
            self.assertEqual("0000000000000000", q_beats[2])

            o_beats = (Path(output_dir) / "smoke_O_golden_beats64.hex").read_text(encoding="ascii").splitlines()
            self.assertEqual(2 * 16, len(o_beats))

    def test_export_rejects_rows_wider_than_stride(self) -> None:
        with tempfile.TemporaryDirectory() as output_dir:
            with self.assertRaisesRegex(ValueError, "stride_bytes"):
                export_case(
                    seed=1,
                    sequence_length=8,
                    dimension=65,
                    max_rows=1,
                    case_name="too_wide",
                    output_dir=Path(output_dir),
                    stride_bytes=128,
                )

    def test_cli_accepts_multiple_seeds_and_suffixes_case_names(self) -> None:
        with tempfile.TemporaryDirectory() as output_dir:
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(REPO_ROOT / "scripts" / "generate_test_vectors.py"),
                    "--seeds",
                    "5,6",
                    "--sequence-length",
                    "8",
                    "--dimension",
                    "8",
                    "--max-rows",
                    "1",
                    "--case-name",
                    "batch",
                    "--output-dir",
                    output_dir,
                ],
                check=False,
                text=True,
                capture_output=True,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("cases=2", result.stdout)
            self.assertTrue((Path(output_dir) / "batch_seed5_metadata.json").exists())
            self.assertTrue((Path(output_dir) / "batch_seed6_metadata.json").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
