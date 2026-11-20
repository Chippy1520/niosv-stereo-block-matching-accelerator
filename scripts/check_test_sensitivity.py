"""Prove selected arithmetic/timing/flush faults are caught by the standalone benches.

Only disposable copies under build/mutation-checks are modified. Real RTL is untouched.
This is a targeted testbench-sensitivity check, not exhaustive fault coverage.
"""
from pathlib import Path
import os
import shutil
import subprocess
import importlib.util
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('rtl_test_runner', ROOT / 'scripts/run_tests.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
BACKEND_SOURCES, SUITES = runner.BACKEND_SOURCES, runner.SUITES
os.environ['PATH'] = str(ROOT / 'tools/mingw64/bin') + os.pathsep + os.environ['PATH']
compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
if not compiler or not runtime:
    raise SystemExit('Icarus Verilog is required.')

datapath_sources = SUITES['datapath'][1]
faults = [
    ('search_reversed_lanes', 'sad_search_backend.sv',
     'right_columns_i[d*COL_BITS +: COL_BITS]', 'right_columns_i[(LANES-1-d)*COL_BITS +: COL_BITS]',
     'tb_sad_search_backend', BACKEND_SOURCES, 'DATAPATH'),
    ('search_skipped_warmup', 'sad_search_backend.sv',
     '.valid_i(valid_i && right_valid_i[d])',
     '.valid_i(valid_i && right_valid_i[d] && x_i >= K+LANES-2)',
     'tb_sad_search_backend', BACKEND_SOURCES, 'DATAPATH'),
    ('search_skewed_x', 'sad_search_backend.sv',
     "assign x_o = valid_o ? tag_x[DELAY] : '0;", "assign x_o = valid_o ? tag_x[DELAY-1] : '0;",
     'tb_sad_search_backend', BACKEND_SOURCES, 'DATAPATH'),
    ('search_partial_winner', 'sad_search_backend.sv',
     'wire full_search = common_valid[ENGINE_DELAY] && (&lane_valid);',
     'wire full_search = (|lane_valid);',
     'tb_sad_search_backend', BACKEND_SOURCES, 'DATAPATH'),
    ('datapath_wrong_record_offset', 'stereo_sad_datapath.sv',
     'result_o[SAD_W +: D_W] = disparity_o;', 'result_o[SAD_W+1 +: D_W] = disparity_o;',
     'tb_stereo_sad_datapath', datapath_sources, 'DATAPATH'),
    ('datapath_invalid_record_not_zero', 'stereo_sad_datapath.sv',
     "result_o = '0;", "result_o = 32'h40000000;",
     'tb_stereo_sad_datapath', datapath_sources, 'DATAPATH'),
    ('datapath_backend_ignores_row_clear', 'stereo_sad_datapath.sv',
     '.clear_i(frame_clear_i || row_clear_i)', '.clear_i(frame_clear_i)',
     'tb_stereo_sad_datapath', datapath_sources, 'SEARCH_PROTOCOL'),
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
     'tb_circular_row_buffer', ['row_ram_bank.sv', 'circular_row_buffer.sv'], 'ROW'),
    ('live_row_slot', 'circular_row_buffer.sv', "{1'b0, read_slot}", "{1'b0, slot}",
     'tb_circular_row_buffer', ['row_ram_bank.sv', 'circular_row_buffer.sv'], 'ROW'),
    ('row_read_on_bubble', 'circular_row_buffer.sv',
     '.enable_i(accept_pixel)', ".enable_i(1'b1)",
     'tb_circular_row_buffer', ['row_ram_bank.sv', 'circular_row_buffer.sv'], 'ROW'),
    ('unregistered_newest_pixel', 'circular_row_buffer.sv',
     "column_present ? newest_pixel : '0", "column_present ? pixel_i : '0",
     'tb_circular_row_buffer', ['row_ram_bank.sv', 'circular_row_buffer.sv'], 'ROW'),
    ('bank_writes_on_read', 'row_ram_bank.sv', 'if (write_i)', "if (1'b1)",
     'tb_row_ram_bank', ['row_ram_bank.sv'], 'RAM'),
    ('reversed_disparity_tie', 'comparator_tree.sv',
     'disparity[level-1][2*node+1] < disparity[level-1][2*node]',
     'disparity[level-1][2*node+1] > disparity[level-1][2*node]',
     'tb_comparator_tree', ['comparator_tree.sv'], 'COMPARATOR'),
    ('invalid_lane_can_win', 'comparator_tree.sv',
     'assign choose_right = active[level-1][2*node+1] &&',
     'assign choose_right = 1\'b1 &&',
     'tb_comparator_tree', ['comparator_tree.sv'], 'COMPARATOR'),
    ('shift_on_bubble', 'right_column_shift.sv', 'if (valid_i) begin',
     "if (1'b1) begin", 'tb_right_column_shift', ['right_column_shift.sv'], 'SHIFT'),
    ('premature_tap_valid', 'right_column_shift.sv',
     'occupied & {TAPS{beat_valid}}', '{TAPS{beat_valid}}',
     'tb_right_column_shift', ['right_column_shift.sv'], 'SHIFT'),
    ('shift_ignores_clear', 'right_column_shift.sv',
     'if (!rst_n || clear_i)', 'if (!rst_n)',
     'tb_right_column_shift', ['right_column_shift.sv'], 'SHIFT'),
    ('delay_bubble_valid', 'left_column_delay.sv', 'valid_o <= valid_i;',
     "valid_o <= 1'b1;", 'tb_left_column_delay', ['left_column_delay.sv'], 'DELAY'),
    ('delay_ignores_clear', 'left_column_delay.sv', 'if (!rst_n || clear_i)',
     'if (!rst_n)', 'tb_left_column_delay', ['left_column_delay.sv'], 'DELAY'),
    ('word_bank_wrong_read_address', 'row_word_bank.sv',
     'read_data_o <= memory[read_address_i];', 'read_data_o <= memory[write_address_i];',
     'tb_row_word_bank', ['row_word_bank.sv'], 'WORD_RAM'),
    ('word_bank_ignores_read_enable', 'row_word_bank.sv', 'if (read_i)', "if (1'b1)",
     'tb_row_word_bank', ['row_word_bank.sv'], 'WORD_RAM'),
    ('word_bank_writes_on_read', 'row_word_bank.sv', 'if (write_i)', 'if (write_i || read_i)',
     'tb_row_word_bank', ['row_word_bank.sv'], 'WORD_RAM'),
    ('packed_live_oldest', 'packed_circular_row_buffer.sv', "{1'b0, oldest}", "{1'b0, read_oldest_i}",
     'tb_packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv'], 'PACKED_ROW'),
    ('packed_reversed_lane', 'packed_circular_row_buffer.sv', "lane <= 2'(read_x_i);", "lane <= ~2'(read_x_i);",
     'tb_packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv'], 'PACKED_ROW'),
    ('packed_load_ignores_clear', 'packed_circular_row_buffer.sv',
     'wire load_word = rst_n && !clear_i && write_valid_i;', 'wire load_word = rst_n && write_valid_i;',
     'tb_packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv'], 'PACKED_ROW'),
    ('packed_bubble_valid', 'packed_circular_row_buffer.sv', 'column_valid_o <= read_column;',
     "column_valid_o <= 1'b1;", 'tb_packed_circular_row_buffer',
     ['row_word_bank.sv', 'packed_circular_row_buffer.sv'], 'PACKED_ROW'),
    ('packed_reads_spare_bank', 'packed_circular_row_buffer.sv',
     '.read_i(read_column && bank_active)', '.read_i(read_column)',
     'tb_packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv'], 'WORD_RAM same-word'),
    ('packed_wraps_at_K', 'packed_circular_row_buffer.sv',
     "? bank_sum - (BANK_W + 1)'(ROW_BANKS) : bank_sum;",
     "? bank_sum - (BANK_W + 1)'(K) : bank_sum;",
     'tb_packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv'], 'PACKED_ROW'),
    ('packed_missing_spare_storage', 'packed_circular_row_buffer.sv',
     'b < ROW_BANKS', 'b < K',
     'tb_packed_circular_row_buffer', ['row_word_bank.sv', 'packed_circular_row_buffer.sv'], 'PACKED_ROW'),
    ('frontend_drops_spare_parameter', 'stereo_frontend.sv',
     '.SPARE_ROWS(SPARE_ROWS)', '.SPARE_ROWS(1)',
     'tb_stereo_frontend', SUITES['frontend'][1], 'PACKED_ROW invalid'),
    ('datapath_drops_spare_parameter', 'stereo_sad_datapath.sv',
     '.SPARE_ROWS(SPARE_ROWS)', '.SPARE_ROWS(1)',
     'tb_stereo_sad_datapath', datapath_sources, 'PACKED_ROW invalid'),
    ('frontend_live_x', 'stereo_frontend.sv', 'x_o <= pending_x;', 'x_o <= read_x_i;',
     'tb_stereo_frontend', ['row_word_bank.sv', 'packed_circular_row_buffer.sv',
                          'left_column_delay.sv', 'right_column_shift.sv', 'stereo_frontend.sv'], 'FRONTEND'),
    ('frontend_ignores_row_clear', 'stereo_frontend.sv',
     'wire history_clear = frame_clear_i || row_clear_i;', 'wire history_clear = frame_clear_i;',
     'tb_stereo_frontend', ['row_word_bank.sv', 'packed_circular_row_buffer.sv',
                          'left_column_delay.sv', 'right_column_shift.sv', 'stereo_frontend.sv'], 'FRONTEND'),
    ('frontend_wrong_right_payload', 'stereo_frontend.sv',
     '.write_data_i(right_write_data_i)', '.write_data_i(left_write_data_i)',
     'tb_stereo_frontend', ['row_word_bank.sv', 'packed_circular_row_buffer.sv',
                          'left_column_delay.sv', 'right_column_shift.sv', 'stereo_frontend.sv'], 'FRONTEND'),
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
    width_param = 'N' if top in ('tb_comparator_tree', 'tb_row_ram_bank', 'tb_row_word_bank') else 'K'
    pixel_bits = 32 if top == 'tb_row_word_bank' else 8
    count = 11
    extra = [f'-P{top}.W=9'] if top in ('tb_packed_circular_row_buffer', 'tb_stereo_frontend') else []
    if top in ('tb_sad_search_backend', 'tb_stereo_sad_datapath'):
        count = 3
        extra = [f'-P{top}.W=13', f'-P{top}.T=3']
    if top in ('tb_packed_circular_row_buffer', 'tb_stereo_frontend', 'tb_stereo_sad_datapath'):
        extra.append(f'-P{top}.S=2')
    compile_result = subprocess.run(
        [compiler, '-g2012', '-I', str(ROOT / 'tests/rtl'), '-s', top, f'-P{top}.{width_param}={count}', f'-P{top}.P={pixel_bits}', *extra,
         '-o', 'mutant.vvp', *source_names, str(ROOT / 'tests/rtl' / f'{top}.sv')],
        cwd=work, capture_output=True, text=True, timeout=60)
    if compile_result.returncode:
        raise SystemExit('Mutation must compile; a syntax error is not a detection:\n' + compile_result.stderr)
    result = subprocess.run([runtime, 'mutant.vvp', '+RANDOM_CYCLES=0'],
                            cwd=work, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    (work / 'result.txt').write_text(output, encoding='utf-8')
    label = marker if marker in ('SEARCH_PROTOCOL', 'WORD_RAM same-word', 'PACKED_ROW invalid') else (
        f'{marker} N=' if width_param == 'N' else f'{marker} K=')
    if result.returncode == 0 or label not in output:
        raise SystemExit(f'FAIL: fault {name} was not caught by the expected scoreboard:\n{output}')
    print(f'PASS sensitivity: {name} rejected by {top} checks')
print(f'PASS: {len(faults)} deliberately faulty designs were detected; real RTL unchanged.')

# Negative protocol/configuration cases must compile and fail with the intended
# real-DUT diagnostic, not the bench's missing-rejection sentinel or a timeout.
guard_messages = [
    'PACKED_ROW SPARE_ROWS must be at least one',
    'Positive dimensions and sufficient address widths are required',
    'PACKED_ROW invalid write address', 'PACKED_ROW invalid column address',
    'invalid write address', 'invalid column address',
    'PACKED_ROW cannot overwrite an active row bank',
    'PACKED_ROW cannot overwrite an active row bank',
    'PACKED_ROW cannot overwrite an active row bank',
]
for fault, message in enumerate(guard_messages):
    work = ROOT / 'build/mutation-checks' / f'packed_guard_{fault}'
    work.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [compiler, '-g2012', '-s', 'tb_packed_row_guards',
         f'-Ptb_packed_row_guards.FAULT={fault}', '-o', 'guard.vvp',
         str(ROOT / 'rtl/row_word_bank.sv'), str(ROOT / 'rtl/packed_circular_row_buffer.sv'),
         str(ROOT / 'tests/rtl/tb_packed_row_guards.sv')],
        cwd=work, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise SystemExit('Guard test must compile:\n' + result.stderr)
    result = subprocess.run([runtime, 'guard.vvp'], cwd=work, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    (work / 'result.txt').write_text(output, encoding='utf-8')
    if result.returncode == 0 or message not in output or 'GUARD_TEST missing' in output:
        raise SystemExit(f'FAIL: guard {fault} did not reject the intended violation:\n{output}')
    print(f'PASS packed guard {fault}: {message}')
print(f'PASS: {len(guard_messages)} spare-row parameter/address/active-bank violations rejected.')

# Keep caller-monitor faults distinct from real-DUT guards and RTL mutations.
subprocess.run([sys.executable, str(ROOT / 'scripts/check_control_sensitivity.py')],
               cwd=ROOT, check=True)
