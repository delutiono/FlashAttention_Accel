#!/usr/bin/env python3
"""Aggressively strip sky130 .lib: remove power, compress NLDM tables to 2x2."""
import re, sys, os

with open(sys.argv[1]) as f:
    text = f.read()

# 1. Remove leakage_power blocks
text = re.sub(r'\n\s*leakage_power\s*\([^)]*\)\s*\{[^}]*\}', '', text)

# 2. Remove internal_power blocks (with brace matching)
while True:
    idx = text.find('internal_power (')
    if idx == -1:
        break
    depth, i = 0, idx
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    text = text[:idx] + text[i+1:]

# 3. Compress NLDM tables: keep only first and last row/col of each table
# Match index_1 and index_2 definitions
def compress_index(m):
    vals = m.group(1)
    parts = [p.strip() for p in vals.split(',')]
    if len(parts) <= 2:
        return m.group(0)
    # Keep first and last
    return f'\n        index_{m.group(2)}("{parts[0]}, {parts[-1]}")'

text = re.sub(r'\n\s*index_(\d+)\("([^"]+)"\)', compress_index, text)

# 4. Compress values tables to 2x2 (keep corners)
def compress_values(m):
    vals_str = m.group(1)
    # Split by comma, handle multiline
    vals = [v.strip() for v in re.split(r'[,\s]+', vals_str) if v.strip()]
    # Filter out template references
    nums = []
    for v in vals:
        try:
            float(v)
            nums.append(v)
        except ValueError:
            pass
    if len(nums) <= 4:
        return m.group(0)
    # For a 7x7 table (49 values), keep indices: 0, 6, 42, 48 (corners of 2x2)
    # But we don't know the exact dimensions. Keep first two and last two.
    n = len(nums)
    if n >= 4:
        corner_vals = [nums[0], nums[1], nums[n-2], nums[n-1]]
        return f'        values ("{", ".join(corner_vals)}")'
    return m.group(0)

text = re.sub(r'\n\s*values\s*\(\s*"([^"]+)"\s*\)', compress_values, text)

# 5. Clean up: remove multiple blank lines, trailing whitespace
text = re.sub(r'\n{3,}', '\n\n', text)
text = re.sub(r'[ \t]+$', '', text, flags=re.M)

with open(sys.argv[2], 'w') as f:
    f.write(text)

orig = os.path.getsize(sys.argv[1]) / 1024 / 1024
new  = os.path.getsize(sys.argv[2]) / 1024 / 1024
print(f"Original: {orig:.1f} MB")
print(f"Stripped: {new:.1f} MB")
print(f"Reduction: {100*(1-new/orig):.0f}%")
