"""Exercise control-emulated integration checks and deliberately bad schedules.

One positive real-DUT run, five caller-protocol faults, then four compiled RTL
mutants. Only disposable copies under build/control-sensitivity are modified.
Caller-monitor rejection is not claimed as synthesized DUT protocol protection.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/control-sensitivity'
TOP = 'tb_stereo_control'
BENCH = ROOT / 'tests/rtl' / f'{TOP}.sv'


def main():
    spec = importlib.util.spec_from_file_location('control_test_runner', ROOT / 'scripts/run_tests.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    sources = runner.SUITES['control'][1]
    os.environ['PATH'] = str(ROOT / 'tools/mingw64/bin') + os.pathsep + os.environ['PATH']
    compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
    if not compiler or not runtime:
        raise SystemExit('Icarus Verilog is required.')
    originals = {name: (ROOT / 'rtl' / name).read_bytes() for name in sources}
    evidence = []
    parameters = [f'-P{TOP}.{key}={value}' for key, value in
                  [('K', 3), ('P', 8), ('W', 9), ('T', 3), ('S', 2)]]

    def compile_case(work, files):
        work.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([compiler, '-g2012', '-Wall', '-s', TOP, *parameters,
                                 '-o', str(work / 'sim.vvp'), *map(str, files), str(BENCH)],
                                cwd=work, capture_output=True, text=True, timeout=60)
        (work / 'compile.txt').write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode:
            raise SystemExit(f'FAIL: sensitivity design must compile: {work}\n{result.stderr}')
        return work / 'sim.vvp'

    def exercise(name, executable, marker, fault=0, positive=False):
        work = WORK / name
        work.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([runtime, str(executable), '+RANDOM_CYCLES=100', '+SEED=123',
                                 f'+CONTROL_FAULT={fault}'], cwd=work,
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        log = work / 'result.txt'
        log.write_text(output, encoding='utf-8')
        if ((result.returncode == 0) != positive or marker not in output):
            raise SystemExit(f'FAIL: {name} did not produce the required diagnostic:\n{output}')
        evidence.append({'name': name, 'exit_code': result.returncode, 'marker': marker,
                         'log': str(log), 'positive': positive})
        print(f'PASS control sensitivity: {name}', flush=True)

    baseline = compile_case(WORK / 'baseline', [ROOT / 'rtl' / name for name in sources])
    exercise('baseline', baseline, 'PASS control K=3', positive=True)
    for fault, name, marker in [
        (1, 'premature_right_tail_promotion', 'CONTROL protocol unready L/R word'),
        (2, 'active_bank_write_during_bubble', 'CONTROL protocol active-bank overwrite'),
        (3, 'clear_before_result_drain', 'CONTROL protocol drain'),
        (4, 'wrong_oldest_rotation', 'CONTROL protocol oldest bank'),
        (5, 'duplicate_read_x', 'CONTROL protocol coordinates'),
    ]:
        exercise(name, baseline, marker, fault=fault)

    mutations = [
        ('wrong_result_record_offset', 'stereo_sad_datapath.sv',
         'result_o[SAD_W +: D_W] = disparity_o;',
         'result_o[SAD_W+1 +: D_W] = disparity_o;'),
        ('right_store_receives_left_pixels', 'stereo_frontend.sv',
         '.write_data_i(right_write_data_i)', '.write_data_i(left_write_data_i)'),
        ('winner_tag_one_cycle_early', 'sad_search_backend.sv',
         "assign x_o = valid_o ? tag_x[DELAY] : '0;",
         "assign x_o = valid_o ? tag_x[DELAY-1] : '0;"),
        ('backend_ignores_busy_frame_clear', 'stereo_sad_datapath.sv',
         '.clear_i(frame_clear_i || row_clear_i)',
         '.clear_i(row_clear_i || (frame_clear_i && !left_valid))'),
    ]
    for name, changed_file, old, new in mutations:
        work = WORK / name
        work.mkdir(parents=True, exist_ok=True)
        for source, content in originals.items():
            text = content.decode('utf-8')
            if source == changed_file:
                if text.count(old) != 1:
                    raise SystemExit(f'FAIL: mutation anchor must be unique: {name}')
                text = text.replace(old, new)
            (work / source).write_text(text, encoding='utf-8')
        executable = compile_case(work, [work / source for source in sources])
        exercise(name, executable, 'CONTROL oracle')
    if any((ROOT / 'rtl' / name).read_bytes() != content for name, content in originals.items()):
        raise SystemExit('FAIL: real RTL changed during sensitivity checking.')
    report = {'checks': evidence, 'protocol_faults': 5, 'rtl_mutants': len(mutations),
              'real_rtl_unchanged': True,
              'source_sha256': {name: hashlib.sha256(content).hexdigest()
                                for name, content in originals.items()},
              'bench_sha256': hashlib.sha256(BENCH.read_bytes()).hexdigest()}
    (WORK / 'evidence.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('PASS: positive integrated baseline, five caller faults and four RTL mutants; real RTL unchanged.')


if __name__ == '__main__':
    main()
