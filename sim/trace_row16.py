#!/usr/bin/env python3
"""Trace row 16 step by step, matching RTL debug output format for comparison."""
import numpy as np
import sys
sys.path.insert(0, '/home/hh/competition')
from model.rtl_behavioral import rtl_dot_product, rtl_score_scale, ExpLUT, NEG_LARGE_Q816

S, D = 256, 64

def load_hex16(path):
    data = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                val = int(line, 16)
                if val >= 0x8000:
                    val = val - 0x10000
                data.append(val)
    return np.array(data, dtype=np.int16).reshape(S, D)

Q = load_hex16('../sim/q_tb.hex')
K = load_hex16('../sim/k_tb.hex')
V = load_hex16('../sim/v_tb.hex')
exp_lut = ExpLUT()

q_row = 16
q_vec = Q[q_row]

m_q816 = np.int32(NEG_LARGE_Q816)
l_q16 = np.uint64(0)
acc_q1632 = np.zeros(D, dtype=np.int64)

print(f"=== Row {q_row} Python model trace ===")

for k_idx in range(S):
    if k_idx > q_row:  # causal mask
        continue

    k_vec = K[k_idx]
    v_vec = V[k_idx]

    dot = rtl_dot_product(q_vec, k_vec)
    score_q816 = rtl_score_scale(dot, 32)

    m_old = m_q816
    m_new = max(m_old, score_q816)
    new_max = score_q816 > m_old

    # P
    diff_p = 0 if score_q816 > m_old else (score_q816 - m_new) >> 8
    P = int(exp_lut.lookup(np.array([diff_p], dtype=np.int16))[0])

    # Alpha
    alpha_needed = (int(m_old) != NEG_LARGE_Q816) and (score_q816 > m_old)
    if m_old == NEG_LARGE_Q816:
        alpha = 0xFFFF
    elif new_max:
        alpha_diff = (int(m_old) - int(m_new)) >> 8
        alpha = int(exp_lut.lookup(np.array([alpha_diff], dtype=np.int16))[0])
    else:
        alpha = 0xFFFF

    # l update
    l_old = int(l_q16)
    l_scaled = (l_old * alpha) >> 16
    l_new_py = l_scaled + P

    # acc update
    acc_old_0 = int(acc_q1632[0]) & 0xFFFFFFFFFFFF
    acc_new_0 = acc_old_0
    if alpha_needed:
        acc_new_0 = (acc_new_0 * alpha) >> 16
    acc_new_0 = (acc_new_0 + (P * int(v_vec[0]) << 8)) & 0xFFFFFFFFFFFF

    # update state
    for d in range(D):
        if alpha_needed:
            acc_q1632[d] = (int(acc_q1632[d]) * alpha) >> 16
        acc_q1632[d] = acc_q1632[d] + (P * int(v_vec[d]) << 8)
    m_q816 = m_new
    l_q16 = np.uint64(l_new_py)

    # Print in RTL-compatible format
    if alpha_needed:
        print(f"  k={k_idx} ALPHA P={P:04x} alpha={alpha:04x} score={score_q816&0xFFFFFF:06x} m_new={m_new&0xFFFFFF:06x} l_old={l_old:08x} l_new={l_new_py:08x} acc_old[0]={acc_old_0:012x} acc_new[0]={acc_new_0:012x}")
    else:
        acc_old_for_print = int(acc_q1632[0]) if k_idx == 0 else acc_old_0
        print(f"  k={k_idx} NORM  P={P:04x} score={score_q816&0xFFFFFF:06x} l_old={l_old:08x} l_new={l_new_py:08x} acc_old[0]={acc_old_0:012x} acc_new[0]={acc_new_0:012x}")

    if k_idx >= 16:  # Only show first 17 k values (up to k=16)
        break

print(f"\nFinal row {q_row}: l={l_q16:08x} acc[0]={int(acc_q1632[0])&0xFFFFFFFFFFFF:012x}")
