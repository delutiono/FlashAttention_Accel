#!/usr/bin/env python3
"""Pack v1 16-bit vector fixtures into stride-padded 128-bit AXI beat hex."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable, Sequence


DEFAULT_TENSORS = ("Q", "K", "V", "O_golden")
FORMAT_VERSION = "test_vector_format_v1"


def parse_word16_file(path: Path) -> list[int]:
    """Read one 16-bit hex word per line and return unsigned lane values."""

    words: list[int] = []
    for line_number, raw in enumerate(path.read_text(encoding="ascii").splitlines(), start=1):
        text = raw.strip()
        if not text:
            continue
        if len(text) != 4:
            raise ValueError(f"{path}:{line_number}: expected a 4-digit int16 hex word")
        try:
            words.append(int(text, 16) & 0xFFFF)
        except ValueError as exc:
            raise ValueError(f"{path}:{line_number}: invalid int16 hex word {text!r}") from exc
    return words


def pack_beat128(values: Sequence[int]) -> str:
    """Pack up to eight int16 lanes into one little-endian 128-bit AXI beat."""

    if len(values) > 8:
        raise ValueError("a 128-bit beat can contain at most eight int16 values")
    beat = 0
    for lane_index, value in enumerate(list(values) + [0] * (8 - len(values))):
        beat |= (value & 0xFFFF) << (16 * lane_index)
    return f"{beat:032X}"


def pack_tensor_words128(
    *,
    input_words: Path,
    output_beats: Path,
    rows: int,
    dimension: int,
    stride_bytes: int,
) -> int:
    """Pack one tensor word file into stride-padded 128-bit beat lines."""

    if rows <= 0:
        raise ValueError("rows must be positive")
    if dimension <= 0:
        raise ValueError("dimension must be positive")
    if stride_bytes <= 0 or stride_bytes % 16 != 0:
        raise ValueError(f"stride_bytes must be a positive multiple of 16 for beats128, got {stride_bytes}")
    if dimension * 2 > stride_bytes:
        raise ValueError(f"stride_bytes {stride_bytes} is smaller than packed row bytes {dimension * 2}")

    words = parse_word16_file(input_words)
    expected_words = rows * dimension
    if len(words) != expected_words:
        raise ValueError(f"{input_words}: expected {expected_words} int16 words, found {len(words)}")

    elements_per_row = stride_bytes // 2
    beats_per_row = stride_bytes // 16
    lines: list[str] = []
    for row_index in range(rows):
        row_words = words[row_index * dimension : (row_index + 1) * dimension]
        padded = row_words + [0] * (elements_per_row - dimension)
        for beat_index in range(beats_per_row):
            start = beat_index * 8
            lines.append(pack_beat128(padded[start : start + 8]))

    output_beats.parent.mkdir(parents=True, exist_ok=True)
    output_beats.write_text("".join(f"{line}\n" for line in lines), encoding="ascii")
    return len(lines)


def _metadata_int(metadata: dict[str, object], key: str, metadata_path: Path) -> int:
    value = metadata.get(key)
    if not isinstance(value, int):
        raise ValueError(f"{metadata_path}: missing integer field {key!r}")
    return value


def _metadata_file(metadata: dict[str, object], key: str, metadata_path: Path) -> dict[str, object]:
    files = metadata.get("files")
    if not isinstance(files, dict):
        raise ValueError(f"{metadata_path}: missing files object")
    info = files.get(key)
    if not isinstance(info, dict):
        raise ValueError(f"{metadata_path}: missing files.{key} object")
    return info


def _metadata_file_path(metadata: dict[str, object], key: str, metadata_path: Path) -> Path:
    info = _metadata_file(metadata, key, metadata_path)
    path = info.get("path")
    if not isinstance(path, str):
        raise ValueError(f"{metadata_path}: missing files.{key}.path")
    return metadata_path.parent / path


def _metadata_file_rows(metadata: dict[str, object], key: str, metadata_path: Path) -> int:
    info = _metadata_file(metadata, key, metadata_path)
    rows = info.get("rows")
    if not isinstance(rows, int):
        raise ValueError(f"{metadata_path}: missing integer field files.{key}.rows")
    return rows


def _read_metadata(metadata_path: Path) -> dict[str, object]:
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{metadata_path}: invalid JSON metadata") from exc
    if not isinstance(metadata, dict):
        raise ValueError(f"{metadata_path}: metadata must be a JSON object")
    if metadata.get("format_version") != FORMAT_VERSION:
        raise ValueError(f"{metadata_path}: unsupported format_version")
    return metadata


def pack_case_from_metadata(
    *,
    metadata_path: Path,
    output_dir: Path,
    tensors: Iterable[str] = DEFAULT_TENSORS,
) -> dict[str, object]:
    """Pack selected tensor word files from one metadata case into beats128 files."""

    metadata = _read_metadata(metadata_path)
    case_name = metadata.get("case_name")
    if not isinstance(case_name, str):
        raise ValueError(f"{metadata_path}: missing case_name")
    dimension = _metadata_int(metadata, "dimension", metadata_path)
    stride_bytes = _metadata_int(metadata, "stride_bytes", metadata_path)
    if stride_bytes % 16 != 0:
        raise ValueError(f"{metadata_path}: stride_bytes must be 16-byte aligned for beats128")

    outputs: dict[str, dict[str, object]] = {}
    for tensor in tensors:
        word_key = f"{tensor}_16b_hex"
        input_words = _metadata_file_path(metadata, word_key, metadata_path)
        rows = _metadata_file_rows(metadata, word_key, metadata_path)
        output_beats = output_dir / f"{case_name}_{tensor}_beats128.hex"
        beat_count = pack_tensor_words128(
            input_words=input_words,
            output_beats=output_beats,
            rows=rows,
            dimension=dimension,
            stride_bytes=stride_bytes,
        )
        outputs[tensor] = {
            "path": str(output_beats),
            "rows": rows,
            "beats": beat_count,
            "beats_per_row": stride_bytes // 16,
        }

    return {
        "case_name": case_name,
        "metadata_path": str(metadata_path),
        "stride_bytes": stride_bytes,
        "beat128_endian": "little-endian bytes; WDATA[15:0] is lowest-column int16",
        "outputs": outputs,
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--tensors",
        default=",".join(DEFAULT_TENSORS),
        help="Comma-separated tensor names to pack. Default: Q,K,V,O_golden.",
    )
    parser.add_argument(
        "--summary-json",
        type=Path,
        default=None,
        help="Optional path to write the machine-readable pack summary.",
    )
    return parser.parse_args()


def _parse_tensors(text: str) -> list[str]:
    tensors = [item.strip() for item in text.split(",") if item.strip()]
    if not tensors:
        raise ValueError("--tensors must contain at least one tensor name")
    return tensors


def main() -> int:
    args = _parse_args()
    try:
        summary = pack_case_from_metadata(
            metadata_path=args.metadata,
            output_dir=args.output_dir,
            tensors=_parse_tensors(args.tensors),
        )
    except ValueError as exc:
        print(f"ERROR {exc}")
        return 2

    if args.summary_json is not None:
        args.summary_json.parent.mkdir(parents=True, exist_ok=True)
        args.summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
