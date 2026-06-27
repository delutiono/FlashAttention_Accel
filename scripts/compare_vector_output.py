#!/usr/bin/env python3
"""Compare DUT attention output hex against a generated O_golden fixture."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


DutFormat = Literal["words16", "beats64"]


@dataclass(frozen=True)
class CompareResult:
    elements: int
    mae: float
    maxae: float
    max_lsb_error: int
    first_failure: dict[str, int] | None
    passed: bool


def _parse_hex_lines(path: Path) -> list[str]:
    try:
        raw_lines = path.read_text(encoding="ascii").splitlines()
    except UnicodeDecodeError as exc:
        raise ValueError(f"{path} is not ASCII hex") from exc
    return [line.strip() for line in raw_lines if line.strip()]


def _int16_from_word(word: int) -> int:
    word &= 0xFFFF
    return word - 0x10000 if word & 0x8000 else word


def _parse_word16_line(line: str, *, path: Path, line_number: int) -> int:
    if len(line) != 4:
        raise ValueError(f"{path}:{line_number}: expected a 4-digit int16 hex word")
    try:
        return _int16_from_word(int(line, 16))
    except ValueError as exc:
        raise ValueError(f"{path}:{line_number}: invalid int16 hex word {line!r}") from exc


def _parse_beat64_line(line: str, *, path: Path, line_number: int) -> list[int]:
    if len(line) != 16:
        raise ValueError(f"{path}:{line_number}: expected a 16-digit 64-bit beat hex word")
    try:
        beat = int(line, 16)
    except ValueError as exc:
        raise ValueError(f"{path}:{line_number}: invalid 64-bit beat hex word {line!r}") from exc
    return [_int16_from_word((beat >> (16 * lane)) & 0xFFFF) for lane in range(4)]


def _read_words16(path: Path) -> list[int]:
    return [
        _parse_word16_line(line, path=path, line_number=index + 1)
        for index, line in enumerate(_parse_hex_lines(path))
    ]


def _read_beats64(
    path: Path,
    *,
    dimension: int,
    rows: int,
    beats_per_row: int,
) -> list[int]:
    lines = _parse_hex_lines(path)
    expected_beats = rows * beats_per_row
    if len(lines) != expected_beats:
        raise ValueError(f"{path}: expected {expected_beats} beats, found {len(lines)}")

    words: list[int] = []
    for row in range(rows):
        row_words: list[int] = []
        for beat_index in range(beats_per_row):
            line_index = row * beats_per_row + beat_index
            row_words.extend(
                _parse_beat64_line(
                    lines[line_index],
                    path=path,
                    line_number=line_index + 1,
                )
            )
        words.extend(row_words[:dimension])
    return words


def load_dut_words(
    path: Path,
    *,
    dut_format: DutFormat,
    dimension: int,
    rows: int,
    beats_per_row: int,
) -> list[int]:
    """Load DUT output words in row-major signed int16 order."""

    if dut_format == "words16":
        words = _read_words16(path)
        expected = rows * dimension
        if len(words) != expected:
            raise ValueError(f"{path}: expected {expected} int16 words, found {len(words)}")
        return words
    if dut_format == "beats64":
        return _read_beats64(
            path,
            dimension=dimension,
            rows=rows,
            beats_per_row=beats_per_row,
        )
    raise ValueError(f"unsupported DUT format {dut_format!r}")


def _metadata_golden_path(metadata_path: Path, metadata: dict[str, object]) -> Path:
    files = metadata.get("files")
    if not isinstance(files, dict):
        raise ValueError(f"{metadata_path}: missing files object")
    golden_info = files.get("O_golden_16b_hex")
    if not isinstance(golden_info, dict):
        raise ValueError(f"{metadata_path}: missing files.O_golden_16b_hex object")
    golden_rel = golden_info.get("path")
    if not isinstance(golden_rel, str):
        raise ValueError(f"{metadata_path}: missing O_golden_16b_hex path")
    return metadata_path.parent / golden_rel


def _read_metadata(metadata_path: Path) -> dict[str, object]:
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{metadata_path}: invalid JSON metadata") from exc
    if not isinstance(metadata, dict):
        raise ValueError(f"{metadata_path}: metadata must be a JSON object")
    return metadata


def _metadata_int(metadata: dict[str, object], key: str, metadata_path: Path) -> int:
    value = metadata.get(key)
    if not isinstance(value, int):
        raise ValueError(f"{metadata_path}: missing integer field {key!r}")
    return value


def compare_vectors(
    *,
    metadata_path: Path,
    dut_hex_path: Path,
    dut_format: DutFormat,
    require_mae: float | None = None,
    require_maxae: float | None = None,
    golden_hex_path: Path | None = None,
) -> CompareResult:
    """Compare DUT output against fixture O_golden and return error metrics."""

    metadata = _read_metadata(metadata_path)
    dimension = _metadata_int(metadata, "dimension", metadata_path)
    rows = _metadata_int(metadata, "output_rows", metadata_path)
    beats_per_row = _metadata_int(metadata, "beats_per_row", metadata_path)

    golden_path = golden_hex_path if golden_hex_path is not None else _metadata_golden_path(metadata_path, metadata)
    golden = load_dut_words(
        golden_path,
        dut_format="words16",
        dimension=dimension,
        rows=rows,
        beats_per_row=beats_per_row,
    )
    dut = load_dut_words(
        dut_hex_path,
        dut_format=dut_format,
        dimension=dimension,
        rows=rows,
        beats_per_row=beats_per_row,
    )
    if len(golden) != len(dut):
        raise ValueError(f"golden/DUT element count mismatch: {len(golden)} != {len(dut)}")

    abs_lsb_errors = [abs(golden_word - dut_word) for golden_word, dut_word in zip(golden, dut)]
    total_lsb_error = sum(abs_lsb_errors)
    max_lsb_error = max(abs_lsb_errors, default=0)
    mae = (total_lsb_error / len(abs_lsb_errors) / 256.0) if abs_lsb_errors else 0.0
    maxae = max_lsb_error / 256.0

    first_failure: dict[str, int] | None = None
    for index, abs_error in enumerate(abs_lsb_errors):
        if abs_error:
            first_failure = {
                "index": index,
                "row": index // dimension,
                "col": index % dimension,
                "golden": golden[index],
                "dut": dut[index],
                "expected": golden[index],
                "got": dut[index],
                "lsb_error": abs_error,
            }
            break

    passed = True
    if require_mae is not None and mae > require_mae:
        passed = False
    if require_maxae is not None and maxae > require_maxae:
        passed = False

    return CompareResult(
        elements=len(abs_lsb_errors),
        mae=mae,
        maxae=maxae,
        max_lsb_error=max_lsb_error,
        first_failure=first_failure,
        passed=passed,
    )


def build_summary(
    *,
    result: CompareResult,
    metadata_path: Path,
    dut_hex_path: Path,
    dut_format: DutFormat,
    require_mae: float | None,
    require_maxae: float | None,
    golden_hex_path: Path | None,
) -> dict[str, object]:
    """Build a machine-readable comparison summary."""

    metadata = _read_metadata(metadata_path)
    resolved_golden_path = (
        golden_hex_path if golden_hex_path is not None else _metadata_golden_path(metadata_path, metadata)
    )
    return {
        "status": "PASS" if result.passed else "FAIL",
        "passed": result.passed,
        "elements": result.elements,
        "mae": result.mae,
        "maxae": result.maxae,
        "max_lsb_error": result.max_lsb_error,
        "first_failure": result.first_failure,
        "metadata_path": str(metadata_path),
        "golden_hex_path": str(resolved_golden_path),
        "dut_hex_path": str(dut_hex_path),
        "dut_format": dut_format,
        "thresholds": {
            "require_mae": require_mae,
            "require_maxae": require_maxae,
        },
        "case_name": metadata.get("case_name"),
        "dimension": _metadata_int(metadata, "dimension", metadata_path),
        "output_rows": _metadata_int(metadata, "output_rows", metadata_path),
        "beats_per_row": _metadata_int(metadata, "beats_per_row", metadata_path),
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--dut-hex", type=Path, required=True)
    parser.add_argument("--format", choices=("words16", "beats64"), default="words16")
    parser.add_argument(
        "--golden-hex",
        type=Path,
        default=None,
        help="Optional golden int16 word hex. Defaults to files.O_golden_16b_hex in metadata.",
    )
    parser.add_argument("--require-mae", type=float, default=None)
    parser.add_argument("--require-maxae", type=float, default=None)
    parser.add_argument(
        "--dump-summary-json",
        type=Path,
        default=None,
        help="Optional path to write a machine-readable comparison summary JSON.",
    )
    return parser.parse_args()


def _format_first_failure(first_failure: dict[str, int] | None) -> str:
    if first_failure is None:
        return "first_failure=none"
    return (
        "first_failure="
        f"index={first_failure['index']} "
        f"row={first_failure['row']} "
        f"col={first_failure['col']} "
        f"expected={first_failure['expected']} "
        f"got={first_failure['got']} "
        f"lsb_error={first_failure['lsb_error']}"
    )


def main() -> int:
    args = _parse_args()
    try:
        result = compare_vectors(
            metadata_path=args.metadata,
            dut_hex_path=args.dut_hex,
            dut_format=args.format,
            require_mae=args.require_mae,
            require_maxae=args.require_maxae,
            golden_hex_path=args.golden_hex,
        )
    except ValueError as exc:
        print(f"ERROR {exc}")
        return 2

    status = "PASS" if result.passed else "FAIL"
    print(
        f"{status} elements={result.elements} "
        f"mae={result.mae:.12g} maxae={result.maxae:.12g} "
        f"max_lsb_error={result.max_lsb_error} "
        f"{_format_first_failure(result.first_failure)}"
    )
    if args.dump_summary_json is not None:
        summary = build_summary(
            result=result,
            metadata_path=args.metadata,
            dut_hex_path=args.dut_hex,
            dut_format=args.format,
            require_mae=args.require_mae,
            require_maxae=args.require_maxae,
            golden_hex_path=args.golden_hex,
        )
        args.dump_summary_json.parent.mkdir(parents=True, exist_ok=True)
        args.dump_summary_json.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return 0 if result.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
