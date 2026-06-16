#!/usr/bin/env python3
"""Generate baseline FlashAttention corner-case vectors.

The preferred path reuses golden_model.py.  If that import fails, this script
prints the import error and falls back to a small pure-Python reference path so
the first corner-vector set can still be generated in minimal environments.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Callable, Dict, Iterable, List, NamedTuple, Sequence, Tuple


S = 256
D = 64
BK = 32
Q88_SCALE = 256
Q88_MIN = -32768
Q88_MAX = 32767
SCALE = 1.0 / 8.0

Matrix = List[List[int]]
GeneratedMap = Dict[str, Tuple[Path, Path, Path, Path, Path]]


class CaseSpec(NamedTuple):
    build: Callable[[], Tuple[Matrix, Matrix, Matrix]]
    causal: bool


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _load_golden_model():
    repo_root = _repo_root()
    if str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))
    try:
        import golden_model  # type: ignore

        return golden_model, None
    except Exception as exc:  # noqa: BLE001 - surfaced to the caller.
        return None, exc


def _q88(value: float) -> int:
    scaled = int(round(max(-128.0, min(127.99609375, value)) * Q88_SCALE))
    return max(Q88_MIN, min(Q88_MAX, scaled))


def _zeros() -> Matrix:
    return [[0 for _ in range(D)] for _ in range(S)]


def _case_zero() -> Tuple[Matrix, Matrix, Matrix]:
    return _zeros(), _zeros(), _zeros()


def _case_causal_i0() -> Tuple[Matrix, Matrix, Matrix]:
    q = _zeros()
    k = _zeros()
    v = _zeros()

    # With all scores tied, causal row 0 has exactly one legal key: k=0.
    v[0][0] = _q88(1.0)
    v[0][1] = _q88(-1.0)
    v[0][2] = _q88(0.5)
    v[1][0] = _q88(-2.0)
    v[255][0] = _q88(4.0)
    return q, k, v


def _case_causal_i255() -> Tuple[Matrix, Matrix, Matrix]:
    q = _zeros()
    k = _zeros()
    v = _zeros()

    # Last causal row can see every key. Make late keys dominate so row 255
    # catches mask/index mistakes near the full-row boundary.
    q[255][0] = _q88(2.0)
    for row in range(S):
        k[row][0] = _q88(-1.0)
        v[row][0] = _q88(-0.25)

    k[0][0] = _q88(0.5)
    k[127][0] = _q88(2.0)
    k[255][0] = _q88(8.0)
    v[0][0] = _q88(1.0)
    v[127][0] = _q88(3.0)
    v[255][0] = _q88(7.0)
    v[255][1] = _q88(-5.0)
    return q, k, v


def _case_tile_boundary() -> Tuple[Matrix, Matrix, Matrix]:
    q = _zeros()
    k = _zeros()
    v = _zeros()

    for row in range(S):
        q[row][0] = _q88(4.0)
        k[row][0] = _q88(-8.0)

    # BK=32 boundary: row31 can see k31 but not k32; row32 can see k32.
    k[31][0] = _q88(16.0)
    k[32][0] = _q88(24.0)

    v[30][0] = _q88(0.25)
    v[31][0] = _q88(6.0)
    v[31][1] = _q88(-3.0)
    v[32][0] = _q88(-7.0)
    v[32][1] = _q88(5.0)
    v[33][0] = _q88(2.0)
    return q, k, v


def _case_non_causal_smoke() -> Tuple[Matrix, Matrix, Matrix]:
    q = _zeros()
    k = _zeros()
    v = _zeros()

    # Non-causal smoke: q0 should be able to attend to a future key. If a
    # causal mask is accidentally applied, row 0 will miss k255/v255.
    q[0][0] = _q88(2.0)
    k[0][0] = _q88(-4.0)
    k[255][0] = _q88(8.0)
    v[0][0] = _q88(-6.0)
    v[255][0] = _q88(6.0)
    v[255][1] = _q88(2.0)
    return q, k, v


def _to_float(matrix: Matrix) -> List[List[float]]:
    return [[value / Q88_SCALE for value in row] for row in matrix]


def _float_to_q88_matrix(matrix: Sequence[Sequence[float]]) -> Matrix:
    return [[_q88(value) for value in row] for row in matrix]


def _attention_fp32_fallback(q_int: Matrix, k_int: Matrix, v_int: Matrix, causal: bool) -> List[List[float]]:
    q = _to_float(q_int)
    k = _to_float(k_int)
    v = _to_float(v_int)
    out: List[List[float]] = []

    for i in range(S):
        scores = []
        valid_keys = range(i + 1) if causal else range(S)
        for j in valid_keys:
            dot = 0.0
            q_row = q[i]
            k_row = k[j]
            for d in range(D):
                dot += q_row[d] * k_row[d]
            scores.append(dot * SCALE)

        row_max = max(scores)
        weights = [math.exp(score - row_max) for score in scores]
        denom = sum(weights)
        out_row = []
        for d in range(D):
            acc = 0.0
            for j, weight in zip(valid_keys, weights):
                acc += weight * v[j][d]
            out_row.append(acc / denom)
        out.append(out_row)

    return out


def _flatten_hex(matrix: Matrix) -> Iterable[str]:
    for row in matrix:
        for value in row:
            yield f"{value & 0xFFFF:04X}"


def _write_hex(path: Path, matrix: Matrix) -> None:
    path.write_text("\n".join(_flatten_hex(matrix)) + "\n", encoding="ascii")


def _hex_unsigned(value: int, bits: int) -> str:
    digits = bits // 4
    return f"{value & ((1 << bits) - 1):0{digits}X}"


def _scaled_score_s32_16(q_row: Sequence[int], k_row: Sequence[int]) -> int:
    raw_dot = 0
    for q_value, k_value in zip(q_row, k_row):
        raw_dot += q_value * k_value
    return raw_dot >> 3


def _numpy_outputs(golden_model, q: Matrix, k: Matrix, v: Matrix, causal: bool) -> Tuple[Matrix, Matrix]:
    np = golden_model.np
    q_np = np.array(q, dtype=np.int16)
    k_np = np.array(k, dtype=np.int16)
    v_np = np.array(v, dtype=np.int16)

    q_f = golden_model.q88_to_float(q_np)
    k_f = golden_model.q88_to_float(k_np)
    v_f = golden_model.q88_to_float(v_np)
    o_ref_f = golden_model.attention_fp32(q_f, k_f, v_f, causal=causal)
    o_ref = golden_model.float_to_q88(o_ref_f).astype(np.int16).tolist()

    o_q88_f = golden_model.flash_attention_q88(q_np, k_np, v_np, causal=causal, tile_size=32)
    o_q88 = golden_model.float_to_q88(o_q88_f).astype(np.int16).tolist()
    return o_ref, o_q88


def _fallback_outputs(q: Matrix, k: Matrix, v: Matrix, causal: bool) -> Tuple[Matrix, Matrix]:
    o_ref = _float_to_q88_matrix(_attention_fp32_fallback(q, k, v, causal))
    # Minimal fallback: without numpy/golden LUT path, keep O_q88 equal to the
    # FP32-quantized reference and make the backend warning visible to users.
    return o_ref, [row[:] for row in o_ref]


def _case_builders():
    return {
        "zero": CaseSpec(_case_zero, True),
        "causal_i0": CaseSpec(_case_causal_i0, True),
        "causal_i255": CaseSpec(_case_causal_i255, True),
        "tile_boundary": CaseSpec(_case_tile_boundary, True),
        "non_causal_smoke": CaseSpec(_case_non_causal_smoke, False),
    }


def _write_debug_skeleton(debug_root: Path, case_name: str, q: Matrix, k: Matrix, v: Matrix, causal: bool) -> None:
    case_dir = debug_root / case_name
    case_dir.mkdir(parents=True, exist_ok=True)

    q_index = 0
    first_score = _scaled_score_s32_16(q[q_index], k[0])
    first_l = 1 << 23
    first_acc_dim0 = v[0][0] << 23
    first_acc_dim1 = v[0][1] << 23
    first_acc_dim2 = v[0][2] << 23

    meta = [
        f"case={case_name}",
        f"S={S}",
        f"D={D}",
        f"BK={BK}",
        f"causal={int(causal)}",
        "score_format=S32.16",
        "l_format=U9.23",
        "acc_format=S17.31",
        "contains=score_tile.hex,mask_valid.hex,m_l_after_tile.hex",
        "subset=q_index=00 only",
        "subset_note=causal_i0 first debug subset covers all 256 K positions for q=0",
        "pipeline_scalar_dim=00",
        f"first_valid_score={_hex_unsigned(first_score, 48)}",
        f"first_valid_m={_hex_unsigned(first_score, 48)}",
        f"first_valid_l={first_l:08X}",
        f"first_valid_acc_dim00={_hex_unsigned(first_acc_dim0, 48)}",
        f"first_valid_acc_dim01={_hex_unsigned(first_acc_dim1, 48)}",
        f"first_valid_acc_dim02={_hex_unsigned(first_acc_dim2, 48)}",
        "first_valid_rule=m=scaled_score,l=1<<23,acc=V<<23",
        f"expected_after_k0_score={_hex_unsigned(first_score, 48)}",
        f"expected_after_k0_m={_hex_unsigned(first_score, 48)}",
        f"expected_after_k0_l={first_l:08X}",
        f"expected_after_k0_acc_dim00={_hex_unsigned(first_acc_dim0, 48)}",
        "expected_after_k0_rule=score=0,l=1<<23,acc_dim0=V[0][0]<<23",
        "expected_after_k1_masked_valid=0",
        f"expected_after_k1_masked_score={_hex_unsigned(_scaled_score_s32_16(q[q_index], k[1]), 48)}",
        f"expected_after_k1_masked_m={_hex_unsigned(first_score, 48)}",
        f"expected_after_k1_masked_l={first_l:08X}",
        f"expected_after_k1_masked_acc_dim00={_hex_unsigned(first_acc_dim0, 48)}",
        "expected_after_k1_masked_rule=no_update_from_after_k0",
        "note=m_l_after_tile is a skeleton for q=00 after each K/V tile; masked scores do not update state",
    ]
    (case_dir / "meta.txt").write_text("\n".join(meta) + "\n", encoding="ascii")

    score_lines = []
    mask_lines = []
    for j in range(S):
        tile = j // BK
        score = _scaled_score_s32_16(q[q_index], k[j])
        valid = (not causal) or j <= q_index
        score_lines.append(f"{q_index:02X} {tile:02X} {j:02X} {_hex_unsigned(score, 48)}")
        mask_lines.append(f"{q_index:02X} {tile:02X} {j:02X} {int(valid)}")
    (case_dir / "score_tile.hex").write_text("\n".join(score_lines) + "\n", encoding="ascii")
    (case_dir / "mask_valid.hex").write_text("\n".join(mask_lines) + "\n", encoding="ascii")

    ml_lines = []
    for tile in range(S // BK):
        ml_lines.append(f"{q_index:02X} {tile:02X} {_hex_unsigned(first_score, 48)} {first_l:08X}")
    (case_dir / "m_l_after_tile.hex").write_text("\n".join(ml_lines) + "\n", encoding="ascii")


def _write_non_causal_smoke_debug_skeleton(debug_root: Path, q: Matrix, k: Matrix, v: Matrix) -> None:
    case_name = "non_causal_smoke"
    case_dir = debug_root / case_name
    case_dir.mkdir(parents=True, exist_ok=True)

    q_index = 0
    tile = 0
    score_k0 = _scaled_score_s32_16(q[q_index], k[0])
    score_k1 = _scaled_score_s32_16(q[q_index], k[1])
    score_k2 = _scaled_score_s32_16(q[q_index], k[2])
    one_u1_23 = 1 << 23
    exp_k0_to_m0 = int(round(math.exp(score_k0 / 65536.0 - score_k1 / 65536.0) * one_u1_23))

    first_valid_l = one_u1_23
    first_valid_acc_dim0 = v[0][0] << 23
    after_k1_l = exp_k0_to_m0 + one_u1_23
    after_k1_acc_dim0 = (v[0][0] * exp_k0_to_m0) + (v[1][0] << 23)
    after_k2_l = after_k1_l + one_u1_23
    after_k2_acc_dim0 = after_k1_acc_dim0 + (v[2][0] << 23)

    acc_after_tile = [0 for _ in range(D)]
    for dim in range(D):
        acc_after_tile[dim] = v[0][dim] * exp_k0_to_m0
        for k_index in range(1, BK):
            acc_after_tile[dim] += v[k_index][dim] << 23

    meta = [
        f"case={case_name}",
        f"S={S}",
        f"D={D}",
        f"BK={BK}",
        "causal=0",
        "score_format=S32.16",
        "exp_format=U1.23",
        "l_format=U9.23",
        "acc_format=S17.31",
        "contains=score_tile.hex,mask_valid.hex,m_l_after_tile.hex,acc_after_tile.hex",
        "subset=q_index=00 first_tile only",
        "subset_note=debug skeleton for non-causal q=0 tile 0; full-vector outputs remain in test_vectors/cases",
        "exp_mode=python_math_exp_skeleton_for_non_equal_k00_only",
        "equal_score_assumption=k01_and_k02_score_equal_m_after_k01",
        f"first_valid_k=00",
        f"first_valid_score={_hex_unsigned(score_k0, 48)}",
        f"first_valid_m={_hex_unsigned(score_k0, 48)}",
        f"first_valid_l={first_valid_l:08X}",
        f"first_valid_acc_dim00={_hex_unsigned(first_valid_acc_dim0, 48)}",
        "first_valid_rule=m=scaled_score,l=1<<23,acc=V<<23",
        "equal_score_first_k=01",
        f"equal_score_first_score={_hex_unsigned(score_k1, 48)}",
        f"equal_score_first_m={_hex_unsigned(score_k1, 48)}",
        f"equal_score_first_l={after_k1_l:08X}",
        f"equal_score_first_acc_dim00={_hex_unsigned(after_k1_acc_dim0, 48)}",
        "second_equal_score_k=02",
        f"second_equal_score_score={_hex_unsigned(score_k2, 48)}",
        f"second_equal_score_m={_hex_unsigned(score_k1, 48)}",
        "second_equal_score_p=00800000",
        "second_equal_score_alpha=00800000",
        "second_equal_score_l_delta=00800000",
        f"second_equal_score_l={after_k2_l:08X}",
        f"second_equal_score_acc_delta_dim00={_hex_unsigned(v[2][0] << 23, 48)}",
        f"second_equal_score_acc_dim00={_hex_unsigned(after_k2_acc_dim0, 48)}",
        "second_equal_score_rule=when score==m,p=1,alpha=1,l+=1<<23,acc+=V<<23",
        "note=acc_after_tile is first-tile skeleton state; non-equal k00 uses python math exp and is not a frozen LUT contract",
    ]
    (case_dir / "meta.txt").write_text("\n".join(meta) + "\n", encoding="ascii")

    score_lines = []
    mask_lines = []
    for k_index in range(BK):
        score = _scaled_score_s32_16(q[q_index], k[k_index])
        score_lines.append(f"{q_index:02X} {tile:02X} {k_index:02X} {_hex_unsigned(score, 48)}")
        mask_lines.append(f"{q_index:02X} {tile:02X} {k_index:02X} 1")
    (case_dir / "score_tile.hex").write_text("\n".join(score_lines) + "\n", encoding="ascii")
    (case_dir / "mask_valid.hex").write_text("\n".join(mask_lines) + "\n", encoding="ascii")
    (case_dir / "m_l_after_tile.hex").write_text(
        f"{q_index:02X} {tile:02X} {_hex_unsigned(score_k1, 48)} {((31 * one_u1_23) + exp_k0_to_m0):08X}\n",
        encoding="ascii",
    )
    acc_lines = [
        f"{q_index:02X} {tile:02X} {dim:02X} {_hex_unsigned(acc, 48)}"
        for dim, acc in enumerate(acc_after_tile)
    ]
    (case_dir / "acc_after_tile.hex").write_text("\n".join(acc_lines) + "\n", encoding="ascii")


def generate_all(output_dir: Path | str = _repo_root() / "test_vectors" / "cases") -> GeneratedMap:
    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    debug_root = out_dir.parent / "debug"

    golden_model, import_error = _load_golden_model()
    if golden_model is None:
        print(f"WARNING: golden_model import failed; using pure-Python fallback: {import_error}", file=sys.stderr)

    generated: GeneratedMap = {}
    for case_name, case_spec in _case_builders().items():
        q, k, v = case_spec.build()
        if golden_model is None:
            o_ref, o_q88 = _fallback_outputs(q, k, v, case_spec.causal)
        else:
            o_ref, o_q88 = _numpy_outputs(golden_model, q, k, v, case_spec.causal)

        paths = tuple(out_dir / f"{case_name}_{tensor}.hex" for tensor in ("Q", "K", "V", "O_ref", "O_q88"))
        for path, matrix in zip(paths, (q, k, v, o_ref, o_q88)):
            _write_hex(path, matrix)
        generated[case_name] = paths  # type: ignore[assignment]

    q, k, v = _case_causal_i0()
    _write_debug_skeleton(debug_root, "causal_i0", q, k, v, True)
    q, k, v = _case_non_causal_smoke()
    _write_non_causal_smoke_debug_skeleton(debug_root, q, k, v)

    return generated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=_repo_root() / "test_vectors" / "cases",
        help="Output directory for corner-case hex files.",
    )
    args = parser.parse_args()

    generated = generate_all(args.out_dir)
    for case_name, paths in generated.items():
        print(f"{case_name}:")
        for path in paths:
            print(f"  {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
