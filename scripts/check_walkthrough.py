"""Fail if the first SystemVerilog code block diverges from the real RTL."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / 'rtl/column_sum_buffer.sv').read_text(encoding='utf-8').rstrip()
note = (root / 'Column Sum Buffer - Code Walkthrough.md').read_text(encoding='utf-8')
match = re.search(r'```systemverilog\n(.*?)\n```', note, re.S)
if not match or match.group(1).rstrip() != source:
    raise SystemExit('FAIL: Refresh the full RTL snapshot in the walkthrough and review line references.')
print('PASS: walkthrough source snapshot matches rtl/column_sum_buffer.sv')
