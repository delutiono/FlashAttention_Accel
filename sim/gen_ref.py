#!/usr/bin/env python3
"""Generate o_ref_tb.hex from q_tb.hex, k_tb.hex, v_tb.hex using RTL behavioral model."""
import numpy as np
import sys
sys.path.insert(0, '/home/hh/competition')
from model.rtl_behavioral import flash_attention_rtl, ExpLUT, RecipLUT
from golden_model import float_to_q88, q88_to_float, attention_fp32, compute_error

S, D = 256, 64

def load_hex(path):
    data = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                val = int(line, 16)
                if val & 0x8000:
                    val = val - 0x10000  # sign-extend 16-bit
                data.append(val)
    return np.array(data, dtype=np.int16).reshape(S, D)

def save_hex(path, arr):
    flat = arr.ravel()
    with open(path, 'w') as f:
        for v in flat:
            f.write(f"{v & 0xFFFF:04X}\n")

Q = load_hex('sim/q_tb.hex')
K = load_hex('sim/k_tb.hex')
V = load_hex('sim/v_tb.hex')

exp_lut = ExpLUT()
recip_lut = RecipLUT()
O = flash_attention_rtl(Q, K, V, causal=True, exp_lut=exp_lut, recip_lut=recip_lut)
save_hex('sim/o_ref_tb.hex', O)

# Quick sanity: compare with golden FP32
from golden_model import attention_fp32, compute_error
q_f = q88_to_float(Q)
k_f = q88_to_float(K)
v_f = q88_to_float(V)
O_ref_f = attention_fp32(q_f, k_f, v_f, causal=True)
O_rtl_f = q88_to_float(O)
report = compute_error(O_ref_f, O_rtl_f, tag="rtl_vs_fp32")
print("RTL behavioral model vs FP32 reference:")
print(report)
