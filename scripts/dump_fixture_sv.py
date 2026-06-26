#!/usr/bin/env python3
"""Dump a v1 vector fixture as a small SystemVerilog include."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


TENSOR_KEYS = ("Q", "K", "V", "O_golden")


def _read_hex_lines(path: Path, *, width: int) -> list[str]:
    lines = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    pattern = re.compile(rf"^[0-9A-Fa-f]{{{width}}}$")
    for line_number, line in enumerate(lines, start=1):
        if not pattern.match(line):
            raise ValueError(f"{path}:{line_number}: expected {width} hex digits")
    return [line.upper() for line in lines]


def _repo_relative(path: Path, repo_root: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def _sv_name(case_name: str) -> str:
    return re.sub(r"[^0-9A-Za-z_]", "_", case_name).upper()


def _metadata_int(metadata: dict[str, object], key: str, metadata_path: Path) -> int:
    value = metadata.get(key)
    if not isinstance(value, int):
        raise ValueError(f"{metadata_path}: missing integer field {key!r}")
    return value


def _metadata_file(metadata: dict[str, object], key: str, metadata_path: Path) -> dict[str, object]:
    files = metadata.get("files")
    if not isinstance(files, dict):
        raise ValueError(f"{metadata_path}: missing files object")
    file_info = files.get(key)
    if not isinstance(file_info, dict):
        raise ValueError(f"{metadata_path}: missing files.{key} object")
    return file_info


def _metadata_file_path(metadata: dict[str, object], key: str, metadata_path: Path) -> Path:
    file_info = _metadata_file(metadata, key, metadata_path)
    rel_path = file_info.get("path")
    if not isinstance(rel_path, str):
        raise ValueError(f"{metadata_path}: missing files.{key}.path")
    return metadata_path.parent / rel_path


def _validate_beat_lanes(word_lines: list[str], beat_lines: list[str], *, rows: int, dimension: int, beats_per_row: int, path: Path) -> None:
    expected_words = rows * dimension
    expected_beats = rows * beats_per_row
    if len(word_lines) != expected_words:
        raise ValueError(f"{path}: expected {expected_words} int16 words, found {len(word_lines)}")
    if len(beat_lines) != expected_beats:
        raise ValueError(f"{path}: expected {expected_beats} 64-bit beats, found {len(beat_lines)}")

    for row in range(rows):
        for beat_index in range(beats_per_row):
            line_index = row * beats_per_row + beat_index
            expected_lanes: list[str] = []
            for lane in range(4):
                col = beat_index * 4 + lane
                if col < dimension:
                    expected_lanes.append(word_lines[row * dimension + col])
                else:
                    expected_lanes.append("0000")
            expected_beat = "".join(reversed(expected_lanes))
            if beat_lines[line_index] != expected_beat:
                raise ValueError(
                    f"{path}:{line_index + 1}: beat64 endian mismatch, "
                    f"expected {expected_beat}, found {beat_lines[line_index]}"
                )


def _format_array(name: str, beats: list[str]) -> list[str]:
    lines = [f"localparam logic [63:0] {name} [0:{len(beats) - 1}] = '{{"]
    for index, beat in enumerate(beats):
        comma = "," if index + 1 < len(beats) else ""
        lines.append(f"    64'h{beat}{comma}")
    lines.append("};")
    return lines


def build_fixture_include(metadata_path: Path, *, repo_root: Path | None = None) -> str:
    """Return SystemVerilog include text for one v1 fixture metadata file."""

    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if not isinstance(metadata, dict):
        raise ValueError(f"{metadata_path}: metadata must be a JSON object")
    if metadata.get("format_version") != "test_vector_format_v1":
        raise ValueError(f"{metadata_path}: unsupported format_version")
    if metadata.get("beat64_endian") != "little-endian bytes; WDATA[15:0] is lowest-column int16":
        raise ValueError(f"{metadata_path}: unsupported beat64_endian")

    repo_root = repo_root if repo_root is not None else metadata_path.resolve().parents[2]
    case_name = metadata.get("case_name")
    if not isinstance(case_name, str):
        raise ValueError(f"{metadata_path}: missing case_name")
    prefix = _sv_name(case_name)
    sequence_length = _metadata_int(metadata, "sequence_length", metadata_path)
    dimension = _metadata_int(metadata, "dimension", metadata_path)
    output_rows = _metadata_int(metadata, "output_rows", metadata_path)
    stride_bytes = _metadata_int(metadata, "stride_bytes", metadata_path)
    beats_per_row = _metadata_int(metadata, "beats_per_row", metadata_path)

    tensor_beats: dict[str, list[str]] = {}
    tensor_paths: dict[str, Path] = {}
    for tensor in TENSOR_KEYS:
        rows = output_rows if tensor == "O_golden" else sequence_length
        word_path = _metadata_file_path(metadata, f"{tensor}_16b_hex", metadata_path)
        beat_path = _metadata_file_path(metadata, f"{tensor}_beats64_hex", metadata_path)
        word_lines = _read_hex_lines(word_path, width=4)
        beat_lines = _read_hex_lines(beat_path, width=16)
        _validate_beat_lanes(
            word_lines,
            beat_lines,
            rows=rows,
            dimension=dimension,
            beats_per_row=beats_per_row,
            path=beat_path,
        )
        tensor_beats[tensor] = beat_lines
        tensor_paths[tensor] = beat_path

    lines = [
        f"// Auto-generated from {_repo_relative(metadata_path, repo_root)}.",
        "// Regenerate with: python -B scripts/dump_fixture_sv.py --metadata <metadata.json> --output <include.svh>",
        f"localparam int {prefix}_SEQUENCE_LENGTH = {sequence_length};",
        f"localparam int {prefix}_DIMENSION = {dimension};",
        f"localparam int {prefix}_OUTPUT_ROWS = {output_rows};",
        f"localparam int {prefix}_STRIDE_BYTES = {stride_bytes};",
        f"localparam int {prefix}_BEATS_PER_ROW = {beats_per_row};",
        f"localparam int {prefix}_QKV_BEATS = {sequence_length * beats_per_row};",
        f"localparam int {prefix}_O_GOLDEN_BEATS = {output_rows * beats_per_row};",
        f'localparam string {prefix}_METADATA_JSON = "{_repo_relative(metadata_path, repo_root)}";',
    ]
    for tensor in TENSOR_KEYS:
        sv_tensor = "O_GOLDEN" if tensor == "O_golden" else tensor
        lines.append(f'localparam string {prefix}_{sv_tensor}_BEATS64_HEX = "{_repo_relative(tensor_paths[tensor], repo_root)}";')
    lines.append("")

    for tensor in TENSOR_KEYS:
        sv_tensor = "O_GOLDEN" if tensor == "O_golden" else tensor
        lines.extend(_format_array(f"{prefix}_{sv_tensor}_BEATS64", tensor_beats[tensor]))
        lines.append("")

    lines.extend(
        [
            f"function automatic logic [15:0] {prefix}_o_golden_word(input int row, input int col);",
            "    logic [63:0] beat;",
            "    int beat_index;",
            "    int lane;",
            f"    beat_index = row * {prefix}_BEATS_PER_ROW + (col / 4);",
            "    lane = col % 4;",
            f"    beat = {prefix}_O_GOLDEN_BEATS64[beat_index];",
            "    return beat[(lane * 16) +: 16];",
            "endfunction",
            "",
        ]
    )
    return "\n".join(lines)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    include_text = build_fixture_include(args.metadata, repo_root=args.repo_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(include_text, encoding="ascii")
    print(f"WROTE {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
