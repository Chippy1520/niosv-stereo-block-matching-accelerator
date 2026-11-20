"""Run tracked, standalone SV module/engine benches plus the original Python reference.

Examples:
  python scripts/run_tests.py
  python scripts/run_tests.py --suite column --case 11:8 --vcd
  python scripts/run_tests.py --suite buffer
  python scripts/run_tests.py --suite engine --seed 123 --random-cycles 5000
  python scripts/run_tests.py --suite comparator --case 32:15
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MATRIX = [(1, 8), (2, 8), (3, 8), (5, 8), (11, 8), (16, 8), (11, 10), (3, 1)]
# Include full raster-width frames and an adjacent odd width to exercise address wrapping.
ROW_MATRIX = [(1, 8, 1), (2, 8, 3), (3, 8, 4), (5, 8, 2), (11, 8, 8),
              (16, 8, 5), (11, 10, 7), (3, 1, 6), (11, 8, 640), (11, 8, 641)]
ROW_BANK_MATRIX = [(1, 1), (1, 8), (2, 8), (3, 8), (7, 10), (16, 8), (640, 8), (641, 8)]
WORD_BANK_MATRIX = [(1, 32), (2, 32), (3, 32), (7, 32), (160, 32), (161, 32), (7, 4), (7, 40)]
PACKED_ROW_MATRIX = [(1, 8, 1), (1, 8, 9), (2, 8, 1), (3, 8, 3), (3, 8, 7),
                     (5, 8, 16), (11, 8, 640), (11, 8, 641), (16, 8, 5), (3, 1, 6), (11, 10, 7)]
FRONTEND_MATRIX = [(1, 8, 1, 1), (1, 8, 9, 3), (2, 8, 1, 3), (3, 8, 7, 5),
                   (3, 8, 16, 5), (5, 8, 3, 7), (11, 8, 640, 32), (11, 8, 641, 7),
                   (16, 8, 5, 3), (3, 1, 6, 4), (11, 10, 7, 5)]
COMPARATOR_MATRIX = [(1, 1), (2, 8), (3, 8), (5, 8), (11, 15),
                     (16, 15), (31, 15), (32, 15)]
SEARCH_MATRIX = [(1, 8, 1, 1), (1, 8, 9, 3), (2, 8, 7, 1), (3, 8, 13, 5),
                 (5, 8, 3, 7), (11, 8, 640, 32), (11, 8, 641, 7),
                 (16, 8, 24, 3), (3, 1, 13, 4), (11, 10, 17, 5)]
IMAGE_SUITES = ('frontend', 'search', 'datapath', 'control')
PACKED_SUITES = ('packed-row', 'frontend', 'datapath', 'control')
# Controller-emulated frames: narrow/empty interiors, odd packed words,
# multiple spares, production-width storage and the default 32-lane geometry.
CONTROL_MATRIX = [(1, 8, 1, 1, 1), (1, 8, 9, 3, 1), (3, 8, 9, 3, 1),
                  (3, 8, 13, 5, 2), (5, 8, 3, 7, 1), (11, 8, 64, 32, 1),
                  (3, 8, 640, 5, 1), (3, 10, 9, 3, 2), (3, 1, 9, 3, 1),
                  (1, 8, 5, 3, 3)]
# Additional K:P:W:T:S cases: multiple spares, narrow rows, non-power-of-two
# bank counts and a production-width odd row. All original cases remain at S=1.
SPARE_MATRIX = [(1, 8, 1, 1, 2), (3, 8, 7, 3, 2),
                (3, 8, 16, 5, 3), (11, 8, 641, 7, 2)]
BACKEND_SOURCES = ['column_sad.sv', 'column_sum_buffer.sv', 'sad_engine.sv',
                   'comparator_tree.sv', 'sad_search_backend.sv']
DATAPATH_SOURCES = ['row_word_bank.sv', 'packed_circular_row_buffer.sv',
                    'left_column_delay.sv', 'right_column_shift.sv',
                    'stereo_frontend.sv', *BACKEND_SOURCES, 'stereo_sad_datapath.sv']
SHIFT_MATRIX = [(1, 1, 1), (1, 8, 3), (3, 8, 1), (3, 8, 5),
                (11, 8, 32), (11, 10, 7), (16, 8, 2), (3, 1, 4)]
SUITES = {
    'column': ('tb_column_sad', ['column_sad.sv']),
    'buffer': ('tb_column_sum_buffer', ['column_sum_buffer.sv']),
    'engine': ('tb_sad_engine', ['column_sad.sv', 'column_sum_buffer.sv', 'sad_engine.sv']),
    'row-bank': ('tb_row_ram_bank', ['row_ram_bank.sv']),
    'row': ('tb_circular_row_buffer', ['row_ram_bank.sv', 'circular_row_buffer.sv']),
    'word-bank': ('tb_row_word_bank', ['row_word_bank.sv']),
    'packed-row': ('tb_packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv']),
    'frontend': ('tb_stereo_frontend', ['row_word_bank.sv', 'packed_circular_row_buffer.sv',
                                      'left_column_delay.sv', 'right_column_shift.sv', 'stereo_frontend.sv']),
    'search': ('tb_sad_search_backend', BACKEND_SOURCES),
    'datapath': ('tb_stereo_sad_datapath', DATAPATH_SOURCES),
    'control': ('tb_stereo_control', DATAPATH_SOURCES),
    'comparator': ('tb_comparator_tree', ['comparator_tree.sv']),
    'shift': ('tb_right_column_shift', ['right_column_shift.sv']),
    'delay': ('tb_left_column_delay', ['left_column_delay.sv']),
    'pairing': ('tb_column_pairing', ['left_column_delay.sv', 'right_column_shift.sv']),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['all', *SUITES, 'legacy'], default='all')
    parser.add_argument('--case', metavar='K:P[:W[:T]]', help='One case; frontend K:P:W:T; word-bank DEPTH:WORD_BITS; row-bank DEPTH:PIXEL_BITS; comparator LANES:SAD_BITS. W is row width or shift/pairing taps.')
    parser.add_argument('--random-cycles', type=int, default=2000)
    parser.add_argument('--seed', type=int, help='Nonzero 32-bit xorshift seed')
    parser.add_argument('--height', type=int, help='Override image height for search/datapath/control benches')
    parser.add_argument('--spare-rows', type=int, help='Override S for packed-row/frontend/datapath/control; minimum one')
    parser.add_argument('--report', type=Path, default=Path('sim/results.txt'),
                        help='Report path relative to the repository, or absolute; isolates concurrent suites')
    parser.add_argument('--vcd', action='store_true', help='Write waveform.vcd per standalone test case')
    parser.add_argument('--timeout', type=int, default=600, help='Per-process wall-clock limit; full raster frontend checks are CPU-heavy')
    args = parser.parse_args()
    width = 32 if args.suite in ('shift', 'pairing') else 8
    taps = 32
    cases = MATRIX
    if args.case:
        try:
            parts = [int(part) for part in args.case.split(':')]
            if len(parts) == 2:
                k, p = parts
            elif len(parts) == 3:
                k, p, width = parts
            elif len(parts) == 4 and args.suite in IMAGE_SUITES:
                k, p, width, taps = parts
            else:
                raise ValueError
            width_limit = 2048 if args.suite in ('row', 'packed-row', *IMAGE_SUITES) else 64
            count_limit = 2048 if args.suite in ('row-bank', 'word-bank') else 64
            pixel_limit = 128 if args.suite == 'word-bank' else 16
            if not (1 <= k <= count_limit and 1 <= p <= pixel_limit and
                    1 <= width <= width_limit and 1 <= taps <= 64):
                raise ValueError
            cases = [(k, p)]
        except ValueError:
            parser.error('Use K:P[:W[:T]], image suites only for T; K<=64 (bank DEPTH<=2048), P<=16 (word-bank<=128), image W<=2048, T<=64; all positive')
    if args.height is not None and (args.suite not in ('search', 'datapath', 'control') or not 1 <= args.height <= 2048):
        parser.error('--height requires search/datapath/control and a value in 1..2048')
    if args.spare_rows is not None and (args.suite not in PACKED_SUITES or not 1 <= args.spare_rows <= 64):
        parser.error('--spare-rows requires packed-row/frontend/datapath/control and a value in 1..64')
    if args.random_cycles < 0 or args.random_cycles > 1000000:
        parser.error('--random-cycles must be between 0 and 1000000')
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    if args.seed is not None and not 1 <= args.seed <= 0xffffffff:
        parser.error('--seed must be a nonzero unsigned 32-bit integer')
    os.environ['PATH'] = str(ROOT / 'tools/mingw64/bin') + os.pathsep + os.environ['PATH']
    compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
    if not compiler or not runtime:
        parser.error('Install Icarus Verilog; iverilog and vvp must be on PATH.')
    report = ROOT / args.report
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text('RTL regression report\n', encoding='utf-8')

    def run(command, cwd):
        try:
            result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=args.timeout)
        except subprocess.TimeoutExpired as exc:
            with report.open('a', encoding='utf-8') as out:
                out.write(f'FAIL: timeout running {command[0]}\n')
            raise SystemExit(str(exc))
        text = result.stdout + result.stderr
        print(text, end='', flush=True)
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
        suite_cases = ROW_MATRIX if suite == 'row' and not args.case else (
            PACKED_ROW_MATRIX if suite == 'packed-row' and not args.case else
            [(n, bits, width) for n, bits in WORD_BANK_MATRIX]
            if suite == 'word-bank' and not args.case else
            [(n, bits, width) for n, bits in ROW_BANK_MATRIX]
            if suite == 'row-bank' and not args.case else
            SHIFT_MATRIX if suite in ('shift', 'pairing') and not args.case else
            [(n, bits, width) for n, bits in COMPARATOR_MATRIX]
            if suite == 'comparator' and not args.case else
            [(k, p, width) for k, p in cases])
        expanded_cases = (SEARCH_MATRIX if suite in ('search', 'datapath') and not args.case else
                          FRONTEND_MATRIX if suite == 'frontend' and not args.case else [
            (k, p, w, taps) for k, p, w in suite_cases])
        if suite == 'control' and not args.case:
            expanded_cases = [(k, p, w, t, args.spare_rows or s) for k, p, w, t, s in CONTROL_MATRIX]
        else:
            expanded_cases = [(k, p, w, t, args.spare_rows or 1) for k, p, w, t in expanded_cases]
        if suite in PACKED_SUITES and suite != 'control' and not args.case and args.spare_rows is None:
            expanded_cases += SPARE_MATRIX
        for k, p, w, t, spare in expanded_cases:
            label = f'n{k}_sad{p}' if suite == 'comparator' else (
                f'n{k}_p{p}' if suite in ('row-bank', 'word-bank') else
                f'k{k}_p{p}_w{w}_t{t}' if suite in IMAGE_SUITES else
                f'k{k}_p{p}_t{w}' if suite in ('shift', 'pairing') else
                f'k{k}_p{p}_w{w}' if suite in ('row', 'packed-row') else f'k{k}_p{p}')
            if suite in PACKED_SUITES:
                label += f'_s{spare}'
            if args.height is not None:
                label += f'_h{args.height}'
            case = ROOT / 'build' / suite / label
            case.mkdir(parents=True, exist_ok=True)
            parameters = [f'-P{top}.N={k}', f'-P{top}.P={p}'] if suite in ('comparator', 'row-bank', 'word-bank') else [
                f'-P{top}.K={k}', f'-P{top}.P={p}']
            if suite in ('row', 'packed-row', *IMAGE_SUITES):
                parameters.append(f'-P{top}.W={w}')
                if suite in IMAGE_SUITES:
                    parameters.append(f'-P{top}.T={t}')
            elif suite in ('shift', 'pairing'):
                parameters.append(f'-P{top}.T={w}')
            if args.height is not None:
                parameters.append(f'-P{top}.H={args.height}')
            if suite in PACKED_SUITES:
                parameters.append(f'-P{top}.S={spare}')
            run([compiler, '-g2012', '-Wall', '-I', str(ROOT / 'tests/rtl'), '-s', top, *parameters, '-o', 'sim.vvp',
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
