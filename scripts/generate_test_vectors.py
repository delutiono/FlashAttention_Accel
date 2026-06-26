#!/usr/bin/env python3
"""Export deterministic Q/K/V/O test vectors for RTL and AXI smoke tests."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from model.golden_fixed import (  # noqa: E402
    DEFAULT_RECIP_LUT_ENTRIES,
    DEFAULT_RECIP_MODE,
    DEFAULT_RECIP_NR_ITERATIONS,
    attention_fixed,
)
from scripts.run_numeric_regression import generate_qkv  # noqa: E402


AXI_DATA_WIDTH_BITS = 64
DEFAULT_STRIDE_BYTES = 128
FORMAT_VERSION = "test_vector_format_v1"


def int16_hex(value: int) -> str:
    """Return an uppercase two's-complement int16 word without a prefix."""

    if value < -32768 or value > 0xFFFF:
        raise ValueError("int16 word value is outside accepted signed/word range")
    return f"{value & 0xFFFF:04X}"


def pack_beat64(values: Sequence[int]) -> str:
    """Pack up to four int16 values into a 64-bit little-endian AXI beat."""

    if len(values) > 4:
        raise ValueError("a 64-bit beat can contain at most four int16 values")
    lanes = list(values) + [0] * (4 - len(values))
    beat = 0
    for lane_index, value in enumerate(lanes):
        beat |= (value & 0xFFFF) << (16 * lane_index)
    return f"{beat:016X}"


def _flatten(matrix: Sequence[Sequence[int]]) -> list[int]:
    return [value for row in matrix for value in row]


def _write_word_hex(path: Path, values: Sequence[int]) -> None:
    path.write_text(
        "".join(f"{int16_hex(value)}\n" for value in values),
        encoding="ascii",
    )


def _write_beat64_hex(
    path: Path,
    rows: Sequence[Sequence[int]],
    *,
    dimension: int,
    stride_bytes: int,
) -> int:
    elements_per_row = stride_bytes // 2
    beats_per_row = stride_bytes // 8
    lines: list[str] = []
    for row in rows:
        padded = list(row[:dimension]) + [0] * (elements_per_row - dimension)
        for beat_index in range(beats_per_row):
            start = beat_index * 4
            lines.append(pack_beat64(padded[start : start + 4]))
    path.write_text("".join(f"{line}\n" for line in lines), encoding="ascii")
    return len(lines)


def _validate_shape(
    *,
    sequence_length: int,
    dimension: int,
    max_rows: int | None,
    stride_bytes: int,
    axi_data_width: int,
) -> int:
    if sequence_length <= 0:
        raise ValueError("sequence_length must be positive")
    if dimension <= 0:
        raise ValueError("dimension must be positive")
    if max_rows is not None and max_rows <= 0:
        raise ValueError("max_rows must be positive when provided")
    if stride_bytes <= 0 or stride_bytes % 8 != 0:
        raise ValueError("stride_bytes must be a positive multiple of 8")
    if dimension * 2 > stride_bytes:
        raise ValueError("stride_bytes must be large enough for one row")
    if axi_data_width != AXI_DATA_WIDTH_BITS:
        raise ValueError("only 64-bit AXI beat export is currently supported")
    return sequence_length if max_rows is None else min(sequence_length, max_rows)


def export_case(
    *,
    seed: int,
    sequence_length: int,
    dimension: int,
    max_rows: int | None,
    case_name: str,
    output_dir: Path,
    stride_bytes: int = DEFAULT_STRIDE_BYTES,
    axi_data_width: int = AXI_DATA_WIDTH_BITS,
) -> dict[str, object]:
    """Generate one deterministic vector case and return its metadata."""

    output_rows = _validate_shape(
        sequence_length=sequence_length,
        dimension=dimension,
        max_rows=max_rows,
        stride_bytes=stride_bytes,
        axi_data_width=axi_data_width,
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    q_rows, k_rows, v_rows = generate_qkv(seed, sequence_length, dimension)
    o_rows = attention_fixed(q_rows, k_rows, v_rows, causal=True, max_rows=max_rows)
    tensors = {
        "Q": q_rows,
        "K": k_rows,
        "V": v_rows,
        "O_golden": o_rows,
    }

    files: dict[str, dict[str, object]] = {}
    for tensor_name, rows in tensors.items():
        word_path = output_dir / f"{case_name}_{tensor_name}.hex"
        beat_path = output_dir / f"{case_name}_{tensor_name}_beats64.hex"
        flat_values = _flatten(rows)
        _write_word_hex(word_path, flat_values)
        beat_count = _write_beat64_hex(
            beat_path,
            rows,
            dimension=dimension,
            stride_bytes=stride_bytes,
        )
        files[f"{tensor_name}_16b_hex"] = {
            "path": word_path.name,
            "rows": len(rows),
            "columns": dimension,
            "elements": len(flat_values),
            "words_per_line": 1,
        }
        files[f"{tensor_name}_beats64_hex"] = {
            "path": beat_path.name,
            "rows": len(rows),
            "columns": dimension,
            "beats": beat_count,
            "beats_per_row": stride_bytes // 8,
        }

    metadata: dict[str, object] = {
        "format_version": FORMAT_VERSION,
        "case_name": case_name,
        "seed": seed,
        "sequence_length": sequence_length,
        "dimension": dimension,
        "max_rows": max_rows,
        "output_rows": output_rows,
        "causal": True,
        "numeric_format": "Q8.8 signed int16",
        "layout": "row_major",
        "word_hex": "one uppercase two's-complement int16 word per line",
        "beat64_endian": "little-endian bytes; WDATA[15:0] is lowest-column int16",
        "stride_bytes": stride_bytes,
        "axi_data_width": axi_data_width,
        "beats_per_row": stride_bytes // 8,
        "generator": "scripts/generate_test_vectors.py",
        "qkv_source": "scripts.run_numeric_regression.generate_qkv",
        "golden_source": "model.golden_fixed.attention_fixed",
        "reciprocal": {
            "mode": DEFAULT_RECIP_MODE,
            "lut_entries": DEFAULT_RECIP_LUT_ENTRIES,
            "nr_iterations": DEFAULT_RECIP_NR_ITERATIONS,
            "valid_latency": 2 + (DEFAULT_RECIP_NR_ITERATIONS << 1),
        },
        "files": files,
    }
    metadata_path = output_dir / f"{case_name}_metadata.json"
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return metadata


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument(
        "--seeds",
        type=str,
        default=None,
        help="Comma-separated seed list. If omitted, --seed is used; if both are omitted seed 100 is used.",
    )
    parser.add_argument("--sequence-length", "-S", type=int, default=256)
    parser.add_argument("--dimension", "-D", type=int, default=64)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--case-name", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--stride-bytes", type=int, default=DEFAULT_STRIDE_BYTES)
    parser.add_argument("--axi-data-width", type=int, default=AXI_DATA_WIDTH_BITS)
    args = parser.parse_args()
    if args.seed is not None and args.seeds is not None:
        parser.error("use either --seed or --seeds, not both")
    return args


def _resolve_seeds(seed: int | None, seeds_text: str | None) -> list[int]:
    if seeds_text is None:
        return [100 if seed is None else seed]
    seeds = [int(item.strip()) for item in seeds_text.split(",") if item.strip()]
    if not seeds:
        raise ValueError("--seeds must contain at least one integer")
    return seeds


def main() -> int:
    args = _parse_args()
    seeds = _resolve_seeds(args.seed, args.seeds)
    exported = []
    for seed in seeds:
        case_name = args.case_name if len(seeds) == 1 else f"{args.case_name}_seed{seed}"
        exported.append(
            export_case(
                seed=seed,
                sequence_length=args.sequence_length,
                dimension=args.dimension,
                max_rows=args.max_rows,
                case_name=case_name,
                output_dir=args.output_dir,
                stride_bytes=args.stride_bytes,
                axi_data_width=args.axi_data_width,
            )
        )
    print(
        "WROTE "
        f"cases={len(exported)} seeds={','.join(str(seed) for seed in seeds)} "
        f"S={args.sequence_length} D={args.dimension} "
        f"max_rows={args.max_rows if args.max_rows is not None else args.sequence_length} "
        f"dir={args.output_dir}"
    )
    print(json.dumps({"cases": exported}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
