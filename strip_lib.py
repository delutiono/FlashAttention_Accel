#!/usr/bin/env python3
"""Strip sky130 .lib down to essentials for Yosys ABC synthesis."""
import re, sys

with open(sys.argv[1]) as f:
    text = f.read()

# Remove all leakage_power blocks (huge, ABC ignores them)
text = re.sub(r'\n\s*leakage_power\s*\([^)]*\)\s*\{[^}]*\}', '', text)

# Remove all internal_power blocks (ABC ignores power)
def remove_blocks(text, block_name):
    while True:
        start = text.find(f'{block_name} (')
        if start == -1:
            break
        depth = 0
        i = start
        while i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        text = text[:start] + text[i+1:]
    return text

text = remove_blocks(text, 'internal_power')

# Remove empty lines, compact whitespace (but keep Liberty structure)
while '\n\n\n' in text:
    text = text.replace('\n\n\n', '\n\n')

with open(sys.argv[2], 'w') as f:
    f.write(text)

# Report sizes
import os
orig = os.path.getsize(sys.argv[1]) / 1024 / 1024
new  = os.path.getsize(sys.argv[2]) / 1024 / 1024
print(f"Original: {orig:.1f} MB")
print(f"Stripped: {new:.1f} MB")
print(f"Reduction: {100*(1-new/orig):.0f}%")
