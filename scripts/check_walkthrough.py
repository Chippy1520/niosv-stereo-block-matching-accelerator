"""Require every functional RTL module to have a source walkthrough and standalone bench."""
from pathlib import Path
import importlib.util
import re

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('rtl_test_runner', ROOT / 'scripts/run_tests.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
SUITES = runner.SUITES
MODULES = {
    'circular_row_buffer': ('Accelerator/Frontend/Circular Row Buffer.md', 'row'),
    'column_sad': ('Accelerator/Engine/Pipelined Column SAD Calculator.md', 'column'),
    'column_sum_buffer': ('Accelerator/Engine/Column Sum Buffer - Code Walkthrough.md', 'buffer'),
    'sad_engine': ('Accelerator/Engine/Single SAD Engine.md', 'engine'),
    'comparator_tree': ('Accelerator/Minimum Comparator Tree - Code Walkthrough.md', 'comparator'),
    'right_column_shift': ('Accelerator/Frontend/Right Column Shift Register.md', 'shift'),
}
# Synthesis-only fixed-width smoke top; its instantiated functional module is covered above.
SYNTHESIS_TOPS = {'circular_row_buffer_synth'}

sources = {file.stem for file in (ROOT / 'rtl').glob('*.sv')}
missing = sources - MODULES.keys() - SYNTHESIS_TOPS
stale = MODULES.keys() - sources
if missing or stale:
    raise SystemExit(f'FAIL: RTL coverage mismatch; missing walkthrough/bench registration: '
                     f'{sorted(missing)}; stale registrations: {sorted(stale)}')
for name, (markdown, suite) in MODULES.items():
    rtl = ROOT / 'rtl' / f'{name}.sv'
    note = ROOT / markdown
    top, suite_sources = SUITES[suite]
    bench = ROOT / 'tests/rtl' / f'{top}.sv'
    if not note.is_file() or not bench.is_file() or f'{name}.sv' not in suite_sources:
        raise SystemExit(f'FAIL: {name} needs a walkthrough, standalone bench and runner suite')
    source = rtl.read_text(encoding='utf-8').rstrip()
    text = note.read_text(encoding='utf-8')
    match = re.search(r'```systemverilog\n(.*?)\n```', text, re.S)
    if not match or match.group(1).rstrip() != source:
        raise SystemExit(f'FAIL: Refresh RTL snapshot in {markdown} and review its explanations')
    bench_text = bench.read_text(encoding='utf-8')
    if not re.search(rf'\bmodule\s+{re.escape(top)}\b', bench_text) or not re.search(
            rf'\b{re.escape(name)}\s*(?:#\s*\(|\w+)', bench_text) or '$fatal' not in bench_text:
        raise SystemExit(f'FAIL: {bench} needs to instantiate {name} and fail on mismatches')
    print(f'PASS: {name}: source walkthrough + self-checking {bench.relative_to(ROOT)}')
