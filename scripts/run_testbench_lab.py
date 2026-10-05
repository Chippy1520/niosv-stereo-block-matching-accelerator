"""Run the small teaching bench; optionally prove it catches two DUT faults.

Outputs and mutated copies stay in build/lab/. Production RTL is never edited.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-faults', action='store_true')
    args = parser.parse_args()
    os.environ['PATH'] = str(ROOT / 'tools/mingw64/bin') + os.pathsep + os.environ['PATH']
    compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
    if not compiler or not runtime:
        parser.error('Install Icarus Verilog (iverilog and vvp).')
    rtl = ROOT / 'rtl/left_column_delay.sv'
    original = rtl.read_bytes()
    work = ROOT / 'build/lab'
    work.mkdir(parents=True, exist_ok=True)

    def simulate(source, label):
        image = work / f'{label}.vvp'
        result = subprocess.run([compiler, '-g2012', '-Wall', '-s', 'tb_delay_lab',
                                 '-o', str(image), str(source),
                                 str(ROOT / 'tests/lab/tb_delay_lab.sv')],
                                cwd=work, text=True, capture_output=True, timeout=60)
        if result.returncode:
            raise SystemExit('Compilation failed, not a scoreboard detection:\n' + result.stderr)
        result = subprocess.run([runtime, str(image), '+VCD'], cwd=work,
                                text=True, capture_output=True, timeout=60)
        text = result.stdout + result.stderr
        (work / f'{label}.log').write_text(text, encoding='utf-8')
        return result.returncode, text

    code, output = simulate(rtl, 'reference')
    print(output, end='')
    if code or 'PASS delay lab: 7 directed beats' not in output:
        raise SystemExit('Teaching baseline failed.')
    # Preserve the good waveform; each fault run otherwise overwrites waveform.vcd.
    shutil.copyfile(work / 'waveform.vcd', work / 'reference.vcd')
    if args.check_faults:
        source = original.decode('utf-8')
        for label, old, new in [
            ('bubble_valid', 'valid_o <= valid_i;', "valid_o <= 1'b1;"),
            ('ignored_clear', 'if (!rst_n || clear_i)', 'if (!rst_n)'),
        ]:
            if source.count(old) != 1:
                raise SystemExit(f'Fault anchor must be unique: {label}')
            mutant = work / f'{label}.sv'
            mutant.write_text(source.replace(old, new), encoding='utf-8')
            code, output = simulate(mutant, label)
            if code == 0 or 'LAB beat=' not in output:
                raise SystemExit(f'Fault not caught by teaching scoreboard: {label}\n{output}')
            print(f'PASS teaching sensitivity: {label} compiled and was rejected')
    if rtl.read_bytes() != original:
        raise SystemExit('Production RTL changed during lab run.')
    print('PASS hands-on lab; real RTL unchanged; good waveform: build/lab/reference.vcd')


if __name__ == '__main__':
    main()
