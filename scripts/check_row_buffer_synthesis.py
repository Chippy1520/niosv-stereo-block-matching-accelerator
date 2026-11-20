"""Synthesize the actual row buffer and reject a logic-only row-memory mapping.

Example (Quartus must be installed, not required for the Icarus CI workflow):
  python scripts/check_row_buffer_synthesis.py --quartus-map C:/intelFPGA_lite/22.1std/quartus/bin64/quartus_map.exe

Uses an isolated project under build/. It does not edit the user's Quartus projects.
This is Analysis & Synthesis, not fitting, timing closure, or board verification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quartus-map', default=shutil.which('quartus_map') or shutil.which('quartus_map.exe'))
    parser.add_argument('--width', type=int, default=640)
    parser.add_argument('--window', type=int, default=11)
    parser.add_argument('--pixel-bits', type=int, default=8)
    parser.add_argument('--timeout', type=int, default=480)
    parser.add_argument('--top', choices=['streaming', 'packed', 'frontend', 'datapath'], default='streaming')
    parser.add_argument('--taps', type=int, default=32)
    parser.add_argument('--spare-rows', type=int, default=1)
    args = parser.parse_args()
    if not args.quartus_map:
        parser.error('Quartus not on PATH; supply --quartus-map /path/to/quartus_map')
    if min(args.width, args.window, args.pixel_bits, args.timeout, args.taps, args.spare_rows) < 1:
        parser.error('width/window/pixel-bits/timeout/taps/spare-rows must be positive')
    if args.top == 'streaming' and args.window < 2:
        parser.error('streaming window must be >=2 for the RAM check; K=1 is a bypass')
    directory, top, sources = {
        'streaming': ('row-buffer-synthesis', 'circular_row_buffer', ['row_ram_bank.sv', 'circular_row_buffer.sv']),
        'packed': ('packed-row-synthesis', 'packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv']),
        'frontend': ('frontend-synthesis', 'stereo_frontend', ['row_word_bank.sv', 'packed_circular_row_buffer.sv',
                                                           'left_column_delay.sv', 'right_column_shift.sv', 'stereo_frontend.sv']),
        'datapath': ('datapath-synthesis', 'stereo_sad_datapath', ['row_word_bank.sv', 'packed_circular_row_buffer.sv',
                    'left_column_delay.sv', 'right_column_shift.sv', 'stereo_frontend.sv', 'column_sad.sv',
                    'column_sum_buffer.sv', 'sad_engine.sv', 'comparator_tree.sv', 'sad_search_backend.sv',
                    'stereo_sad_datapath.sv']),
    }[args.top]
    parent = ROOT / 'build' / directory
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=f'k{args.window}_p{args.pixel_bits}_w{args.width}_t{args.taps}_s{args.spare_rows}_', dir=parent))
    source_bytes = (ROOT / 'rtl' / f'{top}.sv').read_bytes()
    bank_bytes = (ROOT / 'rtl' / sources[0]).read_bytes()
    source_hashes = {}
    for name in sources:
        data = (ROOT / 'rtl' / name).read_bytes()
        (work / name).write_bytes(data)
        source_hashes[name] = hashlib.sha256(data).hexdigest()
    (work / 'row_memory.qpf').write_text('PROJECT_REVISION = "row_memory"\n', encoding='utf-8')
    (work / 'row_memory.qsf').write_text('\n'.join([
        'set_global_assignment -name FAMILY "Cyclone IV E"',
        'set_global_assignment -name DEVICE EP4CE115F29C7',
        f'set_global_assignment -name TOP_LEVEL_ENTITY {top}',
        'set_global_assignment -name NUM_PARALLEL_PROCESSORS 1',
        'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
        *(f'set_global_assignment -name SYSTEMVERILOG_FILE {name}' for name in sources),
        f'set_global_assignment -name SDC_FILE "{(ROOT / "constraints/column_sum_buffer.sdc").as_posix()}"',
        f'set_parameter -name K {args.window}',
        f'set_parameter -name PIXEL_W {args.pixel_bits}',
        f'set_parameter -name IMG_W {args.width}',
        *([f'set_parameter -name SPARE_ROWS {args.spare_rows}'] if args.top != 'streaming' else []),
        *([f'set_parameter -name TAPS {args.taps}'] if args.top == 'frontend' else []),
        *([f'set_parameter -name LANES {args.taps}'] if args.top == 'datapath' else []),
        '',
    ]), encoding='utf-8')
    command = [args.quartus_map, 'row_memory', '--read_settings_files=on', '--write_settings_files=off']
    evidence = {'command': command, 'work': str(work), 'source_sha256': hashlib.sha256(source_bytes).hexdigest(),
                'bank_sha256': hashlib.sha256(bank_bytes).hexdigest(),
                'source_hashes': source_hashes, 'top': top, 'taps': args.taps,
                'K': args.window, 'P': args.pixel_bits, 'W': args.width,
                'spare_rows': args.spare_rows if args.top != 'streaming' else 0,
                'timeout_seconds': args.timeout}
    print('Project:', work, flush=True)
    start = time.monotonic()
    process = subprocess.Popen(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        output, _ = process.communicate(timeout=args.timeout)
        evidence['timed_out'] = False
    except subprocess.TimeoutExpired:
        if os.name == 'nt':
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        else:
            process.kill()
        output, _ = process.communicate()
        evidence['timed_out'] = True
    evidence.update(returncode=process.returncode, elapsed_seconds=round(time.monotonic() - start, 2))
    (work / 'quartus.log').write_text(output, encoding='utf-8')
    summary_file = work / 'output_files/row_memory.map.summary'
    summary = summary_file.read_text(encoding='utf-8', errors='replace') if summary_file.is_file() else ''
    evidence['summary'] = summary
    def number(label):
        match = re.search(r'^' + re.escape(label) + r'\s*:\s*([\d,]+)', summary, re.M)
        return int(match.group(1).replace(',', '')) if match else None
    evidence['logic_elements'] = number('Total logic elements')
    evidence['memory_bits'] = number('Total memory bits')
    evidence['registers'] = number('Total registers')
    report_file = work / 'output_files/row_memory.map.rpt'
    report = report_file.read_text(encoding='utf-8', errors='replace') if report_file.is_file() else ''
    evidence['m9k_ram_nodes'] = len(re.findall(r'^;[^\n]*;\s*M9K\s*;\s*Simple Dual Port\s*;', report, re.M))
    images = 2 if args.top in ('frontend', 'datapath') else 1
    stored_width = args.width if args.top == 'streaming' else ((args.width + 3) // 4) * 4
    row_banks = args.window + (args.spare_rows if args.top != 'streaming' else 0)
    evidence['row_banks_per_image'] = row_banks
    evidence['expected_pixel_bits'] = images * row_banks * stored_width * args.pixel_bits
    evidence['warnings'] = re.findall(r'^Warning[^\n]*', output, re.M)
    evidence['errors'] = re.findall(r'^Error[^\n]*', output, re.M)
    evidence['passed'] = (not evidence['timed_out'] and process.returncode == 0
                          and 'Analysis & Synthesis Status : Successful' in summary
                          and evidence['memory_bits'] is not None
                          and evidence['memory_bits'] >= evidence['expected_pixel_bits']
                          and evidence['m9k_ram_nodes'] >= images * row_banks)
    text = json.dumps(evidence, indent=2)
    (work / 'evidence.json').write_text(text + '\n', encoding='utf-8')
    (parent / 'latest.json').write_text(text + '\n', encoding='utf-8')
    print(summary or output[-6000:])
    print(f'Elapsed: {evidence["elapsed_seconds"]} seconds; warnings={len(evidence["warnings"])} errors={len(evidence["errors"])}')
    print('Evidence:', work / 'evidence.json')
    if not evidence['passed']:
        raise SystemExit('FAIL: synthesis must complete and infer at least the required row-pixel memory bits')
    print(f'PASS: {top} synthesizes with embedded pixel memory (not a logic-only smoke top).')


if __name__ == '__main__':
    main()
