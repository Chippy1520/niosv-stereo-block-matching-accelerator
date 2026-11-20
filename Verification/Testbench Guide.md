# Testbench Guide
#verified

[[Home]] · [[Pipelined Column SAD Calculator]] · [[Column Sum Buffer]] · [[Single SAD Engine]] · [[Circular Row Buffer]] · [[Minimum Comparator Tree - Code Walkthrough]] · [[Verification]]

[[Right Column Shift Register]] — standalone right-column cache, not paired frontend wiring.

**Start [[Hands-on Testbench Lab]] to write your own bench in Questa/ModelSim.** [[Left Column Delay]] and [[Column Pairing Verification]] verify local alignment; [[SAD Search Backend]] and [[Stereo SAD Datapath]] now exercise the connected compute path.

## Module → standalone test → integration → overall test

Each implemented module has its own tracked SystemVerilog testbench:

| Unit                | RTL                        | Testbench                           | Independent reference                                         |
| ------------------- | -------------------------- | ----------------------------------- | ------------------------------------------------------------- |
| Circular row buffer | rtl/circular_row_buffer.sv | tests/rtl/tb_circular_row_buffer.sv | Flat image; rebuild each vertical column from original pixels |
| Internal row RAM bank | rtl/row_ram_bank.sv | tests/rtl/tb_row_ram_bank.sv | Port-written reference memory; clocked reads, disabled writes and bubble holds; ignore write-edge read value |
| Packed-word RAM | rtl/row_word_bank.sv | tests/rtl/tb_row_word_bank.sv | Independent whole-word memory, arbitrary independent addresses, holds and consumer-edge checks |
| Packed row store | rtl/packed_circular_row_buffer.sv | tests/rtl/tb_packed_circular_row_buffer.sv | Flat raw image; K active plus S spare banks, same-word-address spare prefetch, intact-window replay and no-copy rotation |
| Stereo frontend | rtl/stereo_frontend.sv | tests/rtl/tb_stereo_frontend.sv | Separate raw L/R images, direct R[y,x-d] taps and coordinate tags before/after clock edges |
| Full-search backend | rtl/sad_search_backend.sv | tests/rtl/tb_sad_search_backend.sv | Complete raw K×K candidate SADs and serial minimum; exact result edge/tags, all lane costs |
| Complete compute path | rtl/stereo_sad_datapath.sv | tests/rtl/tb_stereo_sad_datapath.sv | Same independent raw-image oracle, real packed loads, exact 32-bit record and consumer-edge checks |
| Control-emulated complete path | Real stereo_sad_datapath, no extra RTL | tests/rtl/tb_stereo_control.sv | Independent accepted-port L/R word/owner monitor, raw K×K winner oracle, pre-/post-edge checks and clocked framebuffer sink |
| Column calculator   | rtl/column_sad.sv          | tests/rtl/tb_column_sad.sv          | Serial sum of K unsigned absolute differences                 |
| Circular buffer     | rtl/column_sum_buffer.sv   | tests/rtl/tb_column_sum_buffer.sv   | Shift K reference columns and recompute their complete sum    |
| Single engine       | rtl/sad_engine.sv          | tests/rtl/tb_sad_engine.sv          | Retain raw pixel columns and recompute the full K×K pixel SAD |
| Comparator tree     | rtl/comparator_tree.sv     | tests/rtl/tb_comparator_tree.sv     | Serial minimum of valid input candidates, including tie ID    |
| Right shift | rtl/right_column_shift.sv | tests/rtl/tb_right_column_shift.sv | Index an append-only log of accepted columns; no reference shift chain |
| Left delay | rtl/left_column_delay.sv | tests/rtl/tb_left_column_delay.sv | Sampled input/hold contract, before/after-edge checks |
| Column pairing (integration) | Both alignment modules | tests/rtl/tb_column_pairing.sv | Independent right-column log and consumer-edge checks |

Expected values never read DUT internal state. The compute benches observe candidate cost/valid outputs inside the backend solely for comparison with independently recomputed full raw-pixel windows; they never use DUT history to generate expectations. Expected values use wider software-style arithmetic rather than the hardware's running recurrence. Every clock checks output validity and output data, including held invalid data and reset/clear behavior. Scoreboards sample after nonblocking updates, avoiding clock-edge races. A mismatch or timeout exits nonzero.

The original Python/deque buffer regression is preserved separately in `scripts/run_buffer_vectors.py`; it generates vectors and a bench under `build/legacy-buffer/`.

## Run commands

From the repository root:

```sh
python scripts/run_tests.py                         # all configured suites
python scripts/run_tests.py --suite row-bank        # bank primitive before row integration
python scripts/run_tests.py --suite word-bank       # word RAM before packed storage
python scripts/run_tests.py --suite packed-row      # independent loads/column reads
python scripts/run_tests.py --suite frontend        # stores + alignment/cache + tags
python scripts/run_tests.py --suite search          # direct-column full-search backend
python scripts/run_tests.py --suite datapath        # real packed loads through winner/record
python scripts/run_tests.py --suite control         # test-only frame/row controller around real top
python scripts/run_tests.py --suite control --case 3:8:9:3 --spare-rows 2 --vcd
python scripts/check_control_sensitivity.py          # positive baseline, bad schedules and RTL wiring faults
python scripts/run_tests.py --suite frontend --case 3:8:7:3 --spare-rows 2
python scripts/run_tests.py --suite datapath --case 3:8:13:5 --spare-rows 3
python scripts/run_tests.py --suite datapath --case 3:8:64:5 --height 480 --random-cycles 0
python scripts/run_tests.py --suite column          # calculator alone
python scripts/run_tests.py --suite buffer          # column-history buffer alone
python scripts/run_tests.py --suite row             # circular row buffer alone
python scripts/run_tests.py --suite engine          # integrated lane
python scripts/run_tests.py --suite comparator      # standalone 1–32-lane tree
python scripts/run_tests.py --suite shift           # whole-column right cache
python scripts/run_tests.py --suite delay           # matching left register
python scripts/run_tests.py --suite pairing         # delay/cache integration
python scripts/run_testbench_lab.py --check-faults  # small teaching baseline
python scripts/run_tests.py --suite legacy          # original Python/deque cases
python scripts/check_walkthrough.py                 # all embedded RTL snapshots
python scripts/check_test_sensitivity.py            # deliberately wrong RTL must fail
```

Calculator, column-history and engine suites use `(K,P) = (1,8), (2,8), (3,8), (5,8), (11,8), (16,8), (11,10), (3,1)`.

The row suite uses `(K,P,W) = (1,8,1), (2,8,3), (3,8,4), (5,8,2), (11,8,8), (16,8,5), (11,10,7), (3,1,6), (11,8,640), (11,8,641)`. The two wide cases each stream 480 source rows before clear/restart/random phases. Default module width remains 640.

The current runner preserves all earlier cases and adds S=2/3 variants to packed-row, frontend and datapath; [the spare-row ledger](../docs/verification/spare-row-prefetch.md) records the actual complete-run outcome. Wide packed-store cases retain **480 rows**. Frontend/packed-compute height is `min(3*(K+S)+5,480)`, so default K=11/S=1 cases use **41 rows**, not 480; the backend-only bench still uses 38 rows. Directed tests plus 2000 stress cycles run by default; legacy cases retain 5000. Seeds are nonzero xorshift32. `--case K:P:W` sets row/packed width; image suites use `K:P:W:T`. `--spare-rows N` selects S for the three packed suites (minimum one; default one), not the standalone serial lesson. `word-bank` uses `DEPTH:WORD_BITS`; `row-bank` uses `DEPTH:PIXEL_BITS`. Shift/pairing use `K:P:T`; comparator uses `LANES:SAD_W`. The per-process bound remains `--timeout` (default 600 seconds). Teaching benches/faults remain separate. Production sensitivity now rejects **38 compiled mutants plus nine explicit contract violations**.

The GUI macro supports `set part word-bank`, `packed-row` and `frontend` before `do scripts/questa_lab.do`, compiling dependencies first. `frontend` uses K=3/P=8/W=9/T=5; the word bank uses N=7/P=32. New RTL/benches compile natively, but fresh simulation is blocked by the already-open user's one-session node-locked license. No user session is closed. Current simulation PASS evidence is Icarus, not a claimed native runtime pass.

Shift matrix `(K,P,T)`: (1,1,1), (1,8,3), (3,8,1), (3,8,5), (11,8,32), (11,10,7), (16,8,2), (3,1,4).

## Controller-emulated integration

See [[Control Emulation]] for the contract and measured evidence. The `control` suite keeps all original benches and adds ten cases from `CONTROL_MATRIX` in `scripts/run_tests.py`. It independently stalls the two input images, withholds the right successor row's final word beyond a row boundary, gates scan start on both complete windows, overlaps spare loads with reads, and drains before a separate row-clear edge. Normal completion is driven by issued reads and fixed latency, not by waiting forever for `row_last_o` on an empty interior.

Four completed frame jobs cover random images, zero ties, maximum differences and a known shift; two additional jobs abort in-flight results where an interior exists. Default control height is `3*(K+S)+3`, not the existing direct-stimulus bench's height. `--height`, `--spare-rows`, `--seed` and `--vcd` work with this suite. `--random-cycles` is its budget for randomized read-pause edges; producer stalls and the directed right-tail wait remain even at zero. `--report` isolates text reports from other concurrent suites.

Each case writes `control_results.csv` and `control_frames.csv` under `build/control/<case>/`. Result rows include job/pattern identity; the frame summary distinguishes completed and intentionally aborted jobs. The sink samples before NBA updates, including the last result on the normal clear edge; post-update checks separately verify pipeline timing and zero-on-invalid packing. No output-ready/backpressure is invented.

The canonical sensitivity command also calls `check_control_sensitivity.py`: one positive real-DUT baseline, five intentionally illegal caller schedules, then three compiled datapath-wiring mutants. Caller-monitor rejection is distinct from synthesized DUT protection. The Questa macro supports `set part control`; current native compile/runtime status and limitations belong in [[Control Emulation]].

## Waveforms

```sh
python scripts/run_tests.py --suite engine --case 11:8 --vcd
python scripts/run_tests.py --suite comparator --case 32:15 --vcd
python scripts/run_tests.py --suite shift --case 11:8:32 --vcd
python scripts/run_tests.py --suite delay --case 3:8 --vcd
python scripts/run_tests.py --suite pairing --case 3:8:3 --vcd
```

Open `build/engine/k11_p8/waveform.vcd` or `build/comparator/n32_sad15/waveform.vcd` in a waveform viewer. The same pattern applies to the other suites. Dumping is opt-in to avoid large default artifacts. Waveforms and build files are not committed.

A tracked bench can also be run directly with Icarus, without the Python runner:

```sh
iverilog -g2012 -s tb_column_sad -o build/column_tb.vvp rtl/column_sad.sv tests/rtl/tb_column_sad.sv
vvp build/column_tb.vvp

iverilog -g2012 -s tb_column_sum_buffer -o build/buffer_tb.vvp rtl/column_sum_buffer.sv tests/rtl/tb_column_sum_buffer.sv
vvp build/buffer_tb.vvp

iverilog -g2012 -s tb_sad_engine -o build/engine_tb.vvp rtl/column_sad.sv rtl/column_sum_buffer.sv rtl/sad_engine.sv tests/rtl/tb_sad_engine.sv
vvp build/engine_tb.vvp

iverilog -g2012 -s tb_comparator_tree -o build/comparator_tb.vvp rtl/comparator_tree.sv tests/rtl/tb_comparator_tree.sv
vvp build/comparator_tb.vvp

iverilog -g2012 -s tb_right_column_shift -o build/shift_tb.vvp rtl/right_column_shift.sv tests/rtl/tb_right_column_shift.sv
vvp build/shift_tb.vvp
```

Create `build/` first if running these manually. Compiler/runtime must be on PATH. Engine-stage benches default to K=11, P=8; the comparator defaults to N=32, P=15. Use `-Ptb_sad_engine.K=3` or `-Ptb_comparator_tree.N=5` to override. Optional vvp arguments are `+RANDOM_CYCLES=5000`, `+SEED=12345`, and `+VCD`.

## Test coverage

- K=1 corner case; odd, non-power-of-two and power-of-two kernels.
- Zero and maximum costs; both unsigned subtraction directions.
- Each packed pixel position individually affects the column result.
- Exact pipeline delay and validity; continuous input and bubbles.
- Buffer warmup, many wraps, ramp inputs, invalid-cycle hold behavior.
- Synchronous reset and clear with simultaneous valid.
- Pipeline flushes at different occupancy offsets.
- Normal row drain/clear transitions; exact output counts and no cross-row mixing.
- Rows too short to form a window.
- End-to-end raw-pixel window results, not merely matching one component's output to another.
- Comparator: zero/maximum costs, every winning physical lane, invalid zero versus valid maximum, equal-cost lower-ID wins, odd padding, bubbles, reset/clear at each occupancy, and a serial independent `(SAD, disparity)` reference.

## Testbench sensitivity

Shift coverage: whole-column packed order, independent per-tap warmup, single/odd tap counts, long history, pause-with-changing-data, clear at every occupancy depth, reset/clear priority and no previous-row leakage. Its waveform is `build/shift/k11_p8_t32/waveform.vcd`.

The sensitivity script mutates only disposable copies under `build/mutation-checks/`. All 38 compiled mutants must fail their expected behavioral/contract checks: arithmetic/history/serial-RAM/timing/tie/valid, word addressing, captured bank/lane tags, clear-suppressed packed writes, bubble validity, frontend tags/LR wiring, backend qualification/packing and the spare-row read-gating/rotation/storage/parameter path. Syntax errors or failures from the wrong checker do not count. `tb_packed_row_guards.sv` separately requires nine specific parameter/address/active-bank diagnostics, including wrapped membership and active writes at a different word. This is targeted sensitivity, not exhaustive mutation/formal coverage. Teaching faults use separate copies.

## Not covered by this milestone

SDRAM-master addressing, autonomous bank ownership/readiness and promotion, cross-group best merge/replay, Avalon wait states, CDC, physical pins, fitted Fmax, Nios V execution and board-level disparity-map accuracy remain later tests. The real packed frontend → engines → comparator → tagged result is tested under explicit testbench scheduling, including spare prefetch and exact no-border-padding qualification. Functional integration is not autonomous control, achieved throughput or physical timing closure.
