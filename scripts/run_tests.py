"""Run tracked, standalone SV module/engine benches plus the original Python reference.

Examples:
  python scripts/run_tests.py
  python scripts/run_tests.py --suite column --case 11:8 --vcd
  python scripts/run_tests.py --suite buffer
  python scripts/run_tests.py --suite engine --seed 123 --random-cycles 5000
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MATRIX = [(1, 8), (2, 8), (3, 8), (5, 8), (11, 8), (16, 8), (11, 10), (3, 1)]
SUITES = {
    'column': ('tb_column_sad', ['column_sad.sv']),
    'buffer': ('tb_column_sum_buffer', ['column_sum_buffer.sv']),
    'engine': ('tb_sad_engine', ['column_sad.sv', 'column_sum_buffer.sv', 'sad_engine.sv']),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['all', 'column', 'buffer', 'engine', 'legacy'], default='all')
    parser.add_argument('--case', metavar='K:PIXEL_BITS', help='One parameter case instead of the default matrix')
    parser.add_argument('--random-cycles', type=int, default=2000)
    parser.add_argument('--seed', type=int, help='Nonzero 32-bit xorshift seed')
    parser.add_argument('--vcd', action='store_true', help='Write waveform.vcd per standalone test case')
    args = parser.parse_args()
    cases = MATRIX
    if args.case:
        try:
            k, p = map(int, args.case.split(':'))
            if not (1 <= k <= 64 and 1 <= p <= 16):
                raise ValueError
            cases = [(k, p)]
        except ValueError:
            parser.error('--case must be K:P with 1<=K<=64 and 1<=P<=16 (testbench limits)')
    if args.random_cycles < 0 or args.random_cycles > 1000000:
        parser.error('--random-cycles must be between 0 and 1000000')
    if args.seed is not None and not 1 <= args.seed <= 0xffffffff:
        parser.error('--seed must be a nonzero unsigned 32-bit integer')
    os.environ['PATH'] = str(ROOT / 'tools/mingw64/bin') + os.pathsep + os.environ['PATH']
    compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
    if not compiler or not runtime:
        parser.error('Install Icarus Verilog; iverilog and vvp must be on PATH.')
    report = ROOT / 'sim/results.txt'
    report.parent.mkdir(exist_ok=True)
    report.write_text('RTL regression report\n', encoding='utf-8')

    def run(command, cwd):
        try:
            result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=120)
        except subprocess.TimeoutExpired as exc:
            with report.open('a', encoding='utf-8') as out:
                out.write(f'FAIL: timeout running {command[0]}\n')
            raise SystemExit(str(exc))
        text = result.stdout + result.stderr
        print(text, end='')
        with report.open('a', encoding='utf-8') as out:
            out.write(text)
            if result.returncode:
                out.write(f'FAIL: process exit code {result.returncode}\n')
        if result.returncode:
            raise SystemExit(result.returncode)

    names = list(SUITES) if args.suite == 'all' else ([args.suite] if args.suite in SUITES else [])
    passed = 0
    for suite in names:
        top, sources = SUITES[suite]
        for k, p in cases:
            case = ROOT / 'build' / suite / f'k{k}_p{p}'
            case.mkdir(parents=True, exist_ok=True)
            run([compiler, '-g2012', '-Wall', '-s', top,
                 f'-P{top}.K={k}', f'-P{top}.P={p}', '-o', 'sim.vvp',
                 *(str(ROOT / 'rtl' / name) for name in sources),
                 str(ROOT / 'tests/rtl' / f'{top}.sv')], case)
            command = [runtime, 'sim.vvp', f'+RANDOM_CYCLES={args.random_cycles}']
            if args.seed is not None:
                command.append(f'+SEED={args.seed}')
            if args.vcd:
                command.append('+VCD')
            run(command, case)
            passed += 1
    if args.suite in ('all', 'legacy'):
        # The legacy Python model intentionally has its own fixed six-case matrix.
        run([sys.executable, str(ROOT / 'scripts/run_buffer_vectors.py')], ROOT)
        passed += 6
    summary = f'PASS: {passed} simulation cases completed; suite={args.suite}.\n'
    print(summary, end='')
    with report.open('a', encoding='utf-8') as out:
        out.write(summary)
    print(f'Report: {report}')


if __name__ == '__main__':
    main()
