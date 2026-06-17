#!/usr/bin/env python3
"""Debug row 1 by comparing RTL and Python model intermediate values."""
import numpy as np
import sys
sys.path.insert(0, '/home/hh/competition')
from model.rtl_behavioral import flash_attention_rtl, ExpLUT, RecipLUT, NEG_LARGE_Q816

S, D = 256, 64

def load_hex(path):
    data = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                val = int(line, 16)
                if val & 0x8000:
                    val = val - 0x10000
                data.append(val)
    return np.array(data, dtype=np.int16).reshape(S, D)

Q = load_hex('sim/q_tb.hex')
K = load_hex('sim/k_tb.hex')
V = load_hex('sim/v_tb.hex')

# Manually compute for row 1
q_row = 1
q_vec = Q[q_row]

m_q816 = np.int32(NEG_LARGE_Q816)
l_q16 = np.uint64(0)
acc_q1632 = np.zeros(D, dtype=np.int64)

exp_lut = ExpLUT()

# Process k=0
k_idx = 0
k_vec = K[k_idx]
v_vec = V[k_idx]
dot_q16 = int(np.dot(q_vec.astype(np.int32), k_vec.astype(np.int32)))
score_q816 = (dot_q16 * 32) >> 8  # scale=32=0.125

print(f"Row 1, k=0:")
print(f"  dot (Q16.16) = {dot_q16:#x}")
print(f"  score (Q8.16) = {score_q816:#x} ({score_q816})")

m_old = m_q816
m_new = max(m_old, score_q816)
print(f"  m_old={m_old}, m_new={m_new}")
print(f"  new_max={score_q816 > m_old}")

diff = 0 if score_q816 > m_old else (score_q816 - m_new) >> 8
print(f"  P diff (Q8.8) = {diff} ({diff:#x})")
P = exp_lut.lookup(np.array([diff], dtype=np.int16))[0]
print(f"  P (Q0.16) = {P:#06x}")

alpha = 0xFFFF  # first score, m_old == NEG_LARGE
l_scaled = (int(l_q16) * alpha) >> 16
l_new = l_scaled + int(P)
print(f"  l_old={l_q16:#010x} l_scaled={l_scaled:#010x} l_new={l_new:#010x}")

for d in range(D):
    acc_q1632[d] = (int(acc_q1632[d]) * alpha) >> 16
    acc_q1632[d] = acc_q1632[d] + (int(P) * int(v_vec[d]) << 8)

print(f"  acc after k=0: acc[0]={acc_q1632[0] & 0xFFFFFFFFFFFF:#014x}")
m_q816 = m_new
l_q16 = np.uint64(l_new)

# Process k=1
k_idx = 1
k_vec = K[k_idx]
v_vec = V[k_idx]
dot_q16 = int(np.dot(q_vec.astype(np.int32), k_vec.astype(np.int32)))
score_q816 = (dot_q16 * 32) >> 8

print(f"\nRow 1, k=1:")
print(f"  dot (Q16.16) = {dot_q16:#x}")
print(f"  score (Q8.16) = {score_q816:#x} ({score_q816})")

m_old = m_q816
m_new = max(m_old, score_q816)
print(f"  m_old={m_old}, m_new={m_new}")
print(f"  new_max={score_q816 > m_old}")

diff = 0 if score_q816 > m_old else (score_q816 - m_new) >> 8
print(f"  P diff (Q8.8) = {diff} ({diff:#x})")
P = exp_lut.lookup(np.array([diff], dtype=np.int16))[0]
print(f"  P (Q0.16) = {P:#06x}")

if m_old == NEG_LARGE_Q816:
    alpha = 0xFFFF
else:
    alpha_diff = (m_old - m_new) >> 8
    alpha = exp_lut.lookup(np.array([alpha_diff], dtype=np.int16))[0]
print(f"  alpha (Q0.16) = {alpha:#06x}")

l_scaled = (int(l_q16) * int(alpha)) >> 16
l_new = l_scaled + int(P)
print(f"  l_old={l_q16:#010x} l_scaled={l_scaled:#010x} l_new={l_new:#010x}")

for d in range(D):
    acc_q1632[d] = (int(acc_q1632[d]) * int(alpha)) >> 16
    acc_q1632[d] = acc_q1632[d] + (int(P) * int(v_vec[d]) << 8)

print(f"  acc after k=1: acc[0]={acc_q1632[0] & 0xFFFFFFFFFFFF:#014x}")

print(f"\nFinal: l={l_new:#010x} acc[0]={acc_q1632[0] & 0xFFFFFFFFFFFF:#014x}")
