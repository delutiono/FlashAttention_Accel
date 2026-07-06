#!/usr/bin/env python3
"""Evaluate INT8 block quantization for the FlashAttention test vectors.

This is a dependency-free companion model for bonus7. It follows the
FlashAttention-3 low-precision idea at accelerator scale: compare per-tensor
INT8 quantization against per-block INT8 quantization, with optional Hadamard
preconditioning for Q/K to spread outliers before quantization.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def _signed16(word: str) -> int:
    value = int(word.strip(), 16)
    return value - 0x10000 if value & 0x8000 else value


def load_q8_8_hex(path: Path, rows: int, cols: int) -> list[list[float]]:
    words = path.read_text().split()
    need = rows * cols
    if len(words) < need:
        raise ValueError(f"{path} has {len(words)} values, need {need}")
    data = [_signed16(w) / 256.0 for w in words[:need]]
    return [data[r * cols : (r + 1) * cols] for r in range(rows)]


def flatten(tensor: list[list[float]]) -> list[float]:
    return [x for row in tensor for x in row]


def tensor_shape(tensor: list[list[float]]) -> tuple[int, int]:
    if not tensor or not tensor[0]:
        raise ValueError("tensor must be non-empty")
    cols = len(tensor[0])
    for row in tensor:
        if len(row) != cols:
            raise ValueError("all rows must have the same width")
    return len(tensor), cols


def quant_scale(values: list[float]) -> float:
    max_abs = max(abs(v) for v in values) if values else 0.0
    return max_abs / 127.0 if max_abs > 0.0 else 1.0 / 127.0


def quantize_values(values: list[float], scale: float) -> list[int]:
    inv = 1.0 / scale
    return [max(-127, min(127, int(round(v * inv)))) for v in values]


def dequantize_values(values: list[int], scale: float) -> list[float]:
    return [v * scale for v in values]


def quantize_per_tensor(tensor: list[list[float]]) -> tuple[list[list[float]], list[float]]:
    rows, cols = tensor_shape(tensor)
    scale = quant_scale(flatten(tensor))
    q = quantize_values(flatten(tensor), scale)
    deq = dequantize_values(q, scale)
    return [deq[r * cols : (r + 1) * cols] for r in range(rows)], [scale]


def quantize_by_row_block_int8(
    tensor: list[list[float]], block_rows: int
) -> tuple[list[list[int]], list[list[float]], list[float]]:
    rows, cols = tensor_shape(tensor)
    qrows = [[0 for _ in range(cols)] for _ in range(rows)]
    out = [[0.0 for _ in range(cols)] for _ in range(rows)]
    scales: list[float] = []
    for start in range(0, rows, block_rows):
        end = min(rows, start + block_rows)
        block = [x for row in tensor[start:end] for x in row]
        scale = quant_scale(block)
        scales.append(scale)
        qblock = quantize_values(block, scale)
        deq = dequantize_values(qblock, scale)
        for local_r, r in enumerate(range(start, end)):
            qrows[r] = qblock[local_r * cols : (local_r + 1) * cols]
            out[r] = deq[local_r * cols : (local_r + 1) * cols]
    return qrows, out, scales


def quantize_by_row_block(
    tensor: list[list[float]], block_rows: int
) -> tuple[list[list[float]], list[float]]:
    _, deq, scales = quantize_by_row_block_int8(tensor, block_rows)
    return deq, scales


def hadamard_inplace(vec: list[float]) -> None:
    n = len(vec)
    if n & (n - 1):
        raise ValueError("Hadamard width must be a power of two")
    step = 1
    while step < n:
        jump = step * 2
        for base in range(0, n, jump):
            for i in range(base, base + step):
                a = vec[i]
                b = vec[i + step]
                vec[i] = a + b
                vec[i + step] = a - b
        step = jump
    norm = 1.0 / math.sqrt(n)
    for i, value in enumerate(vec):
        vec[i] = value * norm


def hadamard_rows(tensor: list[list[float]]) -> list[list[float]]:
    out = [row[:] for row in tensor]
    for row in out:
        hadamard_inplace(row)
    return out


def causal_attention(q: list[list[float]], k: list[list[float]], v: list[list[float]]) -> list[list[float]]:
    rows, cols = tensor_shape(q)
    if tensor_shape(k) != (rows, cols) or tensor_shape(v) != (rows, cols):
        raise ValueError("q/k/v shapes must match")
    scale = 1.0 / math.sqrt(cols)
    out = []
    for i in range(rows):
        scores = []
        for j in range(i + 1):
            dot = sum(q[i][d] * k[j][d] for d in range(cols))
            scores.append(dot * scale)
        max_score = max(scores)
        exps = [math.exp(s - max_score) for s in scores]
        denom = sum(exps)
        row = []
        for d in range(cols):
            acc = 0.0
            for j, weight in enumerate(exps):
                acc += (weight / denom) * v[j][d]
            row.append(acc)
        out.append(row)
    return out


def mean_abs_error(a: list[list[float]], b: list[list[float]]) -> float:
    rows, cols = tensor_shape(a)
    if tensor_shape(b) != (rows, cols):
        raise ValueError("shape mismatch")
    total = 0.0
    for r in range(rows):
        for c in range(cols):
            total += abs(a[r][c] - b[r][c])
    return total / (rows * cols)


def max_abs_error(a: list[list[float]], b: list[list[float]]) -> float:
    rows, cols = tensor_shape(a)
    if tensor_shape(b) != (rows, cols):
        raise ValueError("shape mismatch")
    return max(abs(a[r][c] - b[r][c]) for r in range(rows) for c in range(cols))


def q0_16(scale: float) -> int:
    return max(0, min(0xFFFF, int(round(scale * 65536.0))))


def q8_8_word(value: float) -> int:
    raw = int(round(value * 256.0))
    raw = max(-32768, min(32767, raw))
    return raw & 0xFFFF


def write_int8_hex(path: Path, tensor: list[list[int]]) -> None:
    words = []
    for row in tensor:
        for value in row:
            words.append(f"{value & 0xff:02x}")
    path.write_text("\n".join(words) + "\n")


def write_scale_hex(path: Path, scales: list[float], total_blocks: int) -> None:
    padded = scales + [1.0] * max(0, total_blocks - len(scales))
    path.write_text("\n".join(f"{q0_16(scale):04x}" for scale in padded[:total_blocks]) + "\n")


def write_q8_8_hex(path: Path, tensor: list[list[float]]) -> None:
    path.write_text("\n".join(f"{q8_8_word(value):04x}" for row in tensor for value in row) + "\n")


def input_mae(
    q: list[list[float]], k: list[list[float]], v: list[list[float]],
    dq: list[list[float]], dk: list[list[float]], dv: list[list[float]]
) -> float:
    return (mean_abs_error(q, dq) + mean_abs_error(k, dk) + mean_abs_error(v, dv)) / 3.0


def make_metrics(
    baseline_out: list[list[float]],
    q: list[list[float]],
    k: list[list[float]],
    v: list[list[float]],
    dq: list[list[float]],
    dk: list[list[float]],
    dv: list[list[float]],
    bytes_total: int,
    baseline_bytes: int,
) -> dict[str, float]:
    out = causal_attention(dq, dk, dv)
    return {
        "input_mae": input_mae(q, k, v, dq, dk, dv),
        "output_mae": mean_abs_error(baseline_out, out),
        "output_max_ae": max_abs_error(baseline_out, out),
        "bytes_total": bytes_total,
        "bandwidth_reduction": baseline_bytes / bytes_total,
    }


def evaluate_tensors(
    q: list[list[float]],
    k: list[list[float]],
    v: list[list[float]],
    block_rows: int = 8,
    use_hadamard: bool = False,
) -> dict[str, dict[str, float]]:
    rows, cols = tensor_shape(q)
    if tensor_shape(k) != (rows, cols) or tensor_shape(v) != (rows, cols):
        raise ValueError("q/k/v shapes must match")

    baseline_bytes = rows * cols * 2 * 3
    baseline_out = causal_attention(q, k, v)

    dq_pt, sq_pt = quantize_per_tensor(q)
    dk_pt, sk_pt = quantize_per_tensor(k)
    dv_pt, sv_pt = quantize_per_tensor(v)
    per_tensor_bytes = rows * cols * 3 + 2 * (len(sq_pt) + len(sk_pt) + len(sv_pt))

    dq_blk, sq_blk = quantize_by_row_block(q, block_rows)
    dk_blk, sk_blk = quantize_by_row_block(k, block_rows)
    dv_blk, sv_blk = quantize_by_row_block(v, block_rows)
    block_bytes = rows * cols * 3 + 2 * (len(sq_blk) + len(sk_blk) + len(sv_blk))

    report = {
        "baseline_q8_8": {
            "bytes_total": baseline_bytes,
            "bandwidth_reduction": 1.0,
            "output_mae": 0.0,
            "output_max_ae": 0.0,
            "input_mae": 0.0,
        },
        "per_tensor_int8": make_metrics(
            baseline_out, q, k, v, dq_pt, dk_pt, dv_pt, per_tensor_bytes, baseline_bytes
        ),
        "block_int8": make_metrics(
            baseline_out, q, k, v, dq_blk, dk_blk, dv_blk, block_bytes, baseline_bytes
        ),
    }

    if use_hadamard:
        qh = hadamard_rows(q)
        kh = hadamard_rows(k)
        dqh, sqh = quantize_by_row_block(qh, block_rows)
        dkh, skh = quantize_by_row_block(kh, block_rows)
        dvh, svh = quantize_by_row_block(v, block_rows)
        h_bytes = rows * cols * 3 + 2 * (len(sqh) + len(skh) + len(svh))
        report["block_int8_hadamard"] = make_metrics(
            baseline_out, qh, kh, v, dqh, dkh, dvh, h_bytes, baseline_bytes
        )

    return report


def dump_int8_artifacts(
    prefix: Path,
    q: list[list[float]],
    k: list[list[float]],
    v: list[list[float]],
    block_rows: int,
) -> None:
    rows, _ = tensor_shape(q)
    blocks = (rows + block_rows - 1) // block_rows
    q_i8, q_deq, q_scales = quantize_by_row_block_int8(q, block_rows)
    k_i8, k_deq, k_scales = quantize_by_row_block_int8(k, block_rows)
    v_i8, v_deq, v_scales = quantize_by_row_block_int8(v, block_rows)
    out = causal_attention(q_deq, k_deq, v_deq)

    prefix.parent.mkdir(parents=True, exist_ok=True)
    write_int8_hex(prefix.with_name(prefix.name + "_q_i8.hex"), q_i8)
    write_int8_hex(prefix.with_name(prefix.name + "_k_i8.hex"), k_i8)
    write_int8_hex(prefix.with_name(prefix.name + "_v_i8.hex"), v_i8)
    write_scale_hex(prefix.with_name(prefix.name + "_q_scale.hex"), q_scales, blocks)
    write_scale_hex(prefix.with_name(prefix.name + "_k_scale.hex"), k_scales, blocks)
    write_scale_hex(prefix.with_name(prefix.name + "_v_scale.hex"), v_scales, blocks)
    write_q8_8_hex(prefix.with_name(prefix.name + "_o_ref.hex"), out)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seq", type=int, default=64, help="rows to evaluate from q/k/v hex")
    parser.add_argument("--dim", type=int, default=64)
    parser.add_argument("--block", type=int, default=8)
    parser.add_argument("--hadamard", action="store_true")
    parser.add_argument("--sim-dir", type=Path, default=Path("sim"))
    parser.add_argument("--dump-int8-prefix", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    q = load_q8_8_hex(args.sim_dir / "q_tb.hex", args.seq, args.dim)
    k = load_q8_8_hex(args.sim_dir / "k_tb.hex", args.seq, args.dim)
    v = load_q8_8_hex(args.sim_dir / "v_tb.hex", args.seq, args.dim)
    report = evaluate_tensors(q, k, v, block_rows=args.block, use_hadamard=args.hadamard)
    if args.dump_int8_prefix is not None:
        dump_int8_artifacts(args.dump_int8_prefix, q, k, v, args.block)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
