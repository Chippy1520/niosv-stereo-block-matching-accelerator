"""Prove selected arithmetic/timing/flush faults are caught by the standalone benches.

Only disposable copies under build/mutation-checks are modified. Real RTL is untouched.
This is a targeted testbench-sensitivity check, not exhaustive fault coverage.
"""
from pathlib import Path
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
os.environ['PATH'] = str(ROOT / 'tools/mingw64/bin') + os.pathsep + os.environ['PATH']
compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
if not compiler or not runtime:
    raise SystemExit('Icarus Verilog is required.')

faults = [
    ('missing_pixel', 'column_sad.sv', 'if (j < K)', 'if (j < K-1)',
     'tb_column_sad', ['column_sad.sv'], 'COLUMN'),
    ('early_valid', 'column_sad.sv', 'assign valid_o = valid_pipe[LEVELS];',
     'assign valid_o = valid_pipe[LEVELS-1];',
     'tb_column_sad', ['column_sad.sv'], 'COLUMN'),
    ('ignored_clear', 'column_sum_buffer.sv', 'if (!rst_n || clear_i)', 'if (!rst_n)',
     'tb_column_sum_buffer', ['column_sum_buffer.sv'], 'BUFFER'),
    ('miswired_engine_valid', 'sad_engine.sv', '.valid_i(column_valid)', '.valid_i(valid_i)',
     'tb_sad_engine', ['column_sad.sv', 'column_sum_buffer.sv', 'sad_engine.sv'], 'ENGINE'),
    ('shifted_row_tap', 'circular_row_buffer.sv',
     "tap_sum - (SLOT_W + 1)'(K) : tap_sum",
     "tap_sum - (SLOT_W + 1)'(K - 1) : tap_sum",
     'tb_circular_row_buffer', ['circular_row_buffer.sv'], 'ROW'),
]
for name, changed_file, old, new, top, source_names, marker in faults:
    work = ROOT / 'build/mutation-checks' / name
    work.mkdir(parents=True, exist_ok=True)
    for source in source_names:
        content = (ROOT / 'rtl' / source).read_text(encoding='utf-8')
        if source == changed_file:
            if old not in content:
                raise SystemExit(f'Mutation anchor missing: {name}')
            content = content.replace(old, new)
        (work / source).write_text(content, encoding='utf-8')
    compile_result = subprocess.run(
        [compiler, '-g2012', '-s', top, f'-P{top}.K=11', f'-P{top}.P=8',
         '-o', 'mutant.vvp', *source_names, str(ROOT / 'tests/rtl' / f'{top}.sv')],
        cwd=work, capture_output=True, text=True, timeout=60)
    if compile_result.returncode:
        raise SystemExit('Mutation must compile; a syntax error is not a detection:\n' + compile_result.stderr)
    result = subprocess.run([runtime, 'mutant.vvp', '+RANDOM_CYCLES=0'],
                            cwd=work, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    (work / 'result.txt').write_text(output, encoding='utf-8')
    if result.returncode == 0 or f'{marker} K=' not in output:
        raise SystemExit(f'FAIL: fault {name} was not caught by the expected scoreboard:\n{output}')
    print(f'PASS sensitivity: {name} rejected by {top} scoreboard')
print(f'PASS: {len(faults)} deliberately faulty designs were detected; real RTL unchanged.')
