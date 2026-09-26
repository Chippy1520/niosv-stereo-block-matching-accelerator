"""Require each study note's first SystemVerilog block to match its RTL source."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
pairs = [
    ('rtl/column_sum_buffer.sv', 'Column Sum Buffer - Code Walkthrough.md'),
    ('rtl/column_sad.sv', 'Pipelined Column SAD Calculator.md'),
    ('rtl/sad_engine.sv', 'Single SAD Engine.md'),
    ('rtl/circular_row_buffer.sv', 'Circular Row Buffer.md'),
]
for rtl, markdown in pairs:
    source = (root / rtl).read_text(encoding='utf-8').rstrip()
    note = (root / markdown).read_text(encoding='utf-8')
    match = re.search(r'```systemverilog\n(.*?)\n```', note, re.S)
    if not match or match.group(1).rstrip() != source:
        raise SystemExit(f'FAIL: Refresh the full RTL snapshot in {markdown} and review explanations.')
    print(f'PASS: source snapshot matches {rtl}')
