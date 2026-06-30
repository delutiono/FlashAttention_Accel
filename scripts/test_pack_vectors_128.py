#!/usr/bin/env python3
"""Unit tests for 128-bit vector beat packing."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import unittest
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.compare_vector_output import compare_vectors
from scripts.pack_vectors_128 import pack_beat128, pack_case_from_metadata, pack_tensor_words128


TEST_TMP_ROOT = REPO_ROOT / "build" / "test_tmp" / "pack_vectors_128"


class TestPackVectors128(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp_dirs: list[Path] = []

    def tearDown(self) -> None:
        for tmp_dir in reversed(self._tmp_dirs):
            shutil.rmtree(tmp_dir, ignore_errors=True)

    def make_tmp_dir(self) -> Path:
        path = TEST_TMP_ROOT / f"{self._testMethodName}_{uuid.uuid4().hex}"
        path.mkdir(parents=True)
        self._tmp_dirs.append(path)
        return path

    def write_words(self, path: Path, values: list[int]) -> None:
        path.write_text("".join(f"{value & 0xFFFF:04X}\n" for value in values), encoding="ascii")

    def test_pack_beat128_uses_little_endian_int16_lanes(self) -> None:
        self.assertEqual(
            "FFFC0004FFFD0003FFFE0002FFFF0001",
            pack_beat128([1, -1, 2, -2, 3, -3, 4, -4]),
        )

    def test_pack_tensor_words128_writes_stride_padding(self) -> None:
        tmp_path = self.make_tmp_dir()
        input_words = tmp_path / "words.hex"
        output_beats = tmp_path / "beats128.hex"
        self.write_words(input_words, list(range(1, 11)))

        beats = pack_tensor_words128(
            input_words=input_words,
            output_beats=output_beats,
            rows=1,
            dimension=10,
            stride_bytes=32,
        )

        self.assertEqual(2, beats)
        self.assertEqual(
            [
                "00080007000600050004000300020001",
                "000000000000000000000000000A0009",
            ],
            output_beats.read_text(encoding="ascii").splitlines(),
        )

    def test_pack_case_from_metadata_packs_qkv_and_shorter_o_golden(self) -> None:
        tmp_path = self.make_tmp_dir()
        vector_dir = tmp_path / "vectors"
        output_dir = tmp_path / "beats128"
        vector_dir.mkdir()
        case_name = "smoke_s2_d10"
        tensor_values = {
            "Q": list(range(1, 21)),
            "K": list(range(101, 121)),
            "V": list(range(201, 221)),
            "O_golden": list(range(301, 311)),
        }
        files: dict[str, dict[str, object]] = {}
        for tensor, values in tensor_values.items():
            word_path = vector_dir / f"{case_name}_{tensor}.hex"
            self.write_words(word_path, values)
            files[f"{tensor}_16b_hex"] = {
                "path": word_path.name,
                "rows": 1 if tensor == "O_golden" else 2,
                "columns": 10,
                "elements": len(values),
                "words_per_line": 1,
            }
        metadata_path = vector_dir / f"{case_name}_metadata.json"
        metadata_path.write_text(
            json.dumps(
                {
                    "format_version": "test_vector_format_v1",
                    "case_name": case_name,
                    "sequence_length": 2,
                    "dimension": 10,
                    "output_rows": 1,
                    "stride_bytes": 32,
                    "files": files,
                }
            )
            + "\n",
            encoding="utf-8",
        )

        summary = pack_case_from_metadata(metadata_path=metadata_path, output_dir=output_dir)

        self.assertEqual(2, summary["outputs"]["O_golden"]["beats"])
        self.assertEqual(4, summary["outputs"]["Q"]["beats"])
        q_lines = (output_dir / f"{case_name}_Q_beats128.hex").read_text(encoding="ascii").splitlines()
        o_lines = (output_dir / f"{case_name}_O_golden_beats128.hex").read_text(encoding="ascii").splitlines()
        self.assertEqual("00080007000600050004000300020001", q_lines[0])
        self.assertEqual("000000000000000000000000000A0009", q_lines[1])
        self.assertEqual(4, len(q_lines))
        self.assertEqual(2, len(o_lines))

        result = compare_vectors(
            metadata_path=metadata_path,
            dut_hex_path=output_dir / f"{case_name}_O_golden_beats128.hex",
            dut_format="beats128",
            require_mae=0.0,
            require_maxae=0.0,
        )
        self.assertTrue(result.passed)

    def test_cli_writes_summary_json(self) -> None:
        tmp_path = self.make_tmp_dir()
        vector_dir = tmp_path / "vectors"
        output_dir = tmp_path / "beats128"
        vector_dir.mkdir()
        case_name = "cli_s1_d8"
        for tensor in ("Q", "K", "V", "O_golden"):
            self.write_words(vector_dir / f"{case_name}_{tensor}.hex", list(range(1, 9)))
        metadata_path = vector_dir / f"{case_name}_metadata.json"
        metadata_path.write_text(
            json.dumps(
                {
                    "format_version": "test_vector_format_v1",
                    "case_name": case_name,
                    "dimension": 8,
                    "stride_bytes": 16,
                    "files": {
                        f"{tensor}_16b_hex": {
                            "path": f"{case_name}_{tensor}.hex",
                            "rows": 1,
                        }
                        for tensor in ("Q", "K", "V", "O_golden")
                    },
                }
            )
            + "\n",
            encoding="utf-8",
        )
        summary_path = tmp_path / "summary.json"

        result = subprocess.run(
            [
                sys.executable,
                "-B",
                str(REPO_ROOT / "scripts" / "pack_vectors_128.py"),
                "--metadata",
                str(metadata_path),
                "--output-dir",
                str(output_dir),
                "--summary-json",
                str(summary_path),
            ],
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        self.assertEqual(case_name, summary["case_name"])
        self.assertEqual(1, summary["outputs"]["Q"]["beats_per_row"])
        self.assertTrue((output_dir / f"{case_name}_Q_beats128.hex").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
