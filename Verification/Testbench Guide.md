# Testbench Guide
#verified

[[Home]] · [[Pipelined Column SAD Calculator]] · [[Column Sum Buffer]] · [[Single SAD Engine]] · [[Circular Row Buffer]] · [[Minimum Comparator Tree - Code Walkthrough]] · [[Verification]]

[[Right Column Shift Register]] — standalone right-column cache, not paired frontend wiring.

## Module → standalone test → integration → overall test

Each implemented module has its own tracked SystemVerilog testbench:

| Unit | RTL | Testbench | Independent reference |
|---|---|---|---|
| Circular row buffer | rtl/circular_row_buffer.sv | tests/rtl/tb_circular_row_buffer.sv | Flat image; rebuild each vertical column from original pixels |
| Column calculator | rtl/column_sad.sv | tests/rtl/tb_column_sad.sv | Serial sum of K unsigned absolute differences |
| Circular buffer | rtl/column_sum_buffer.sv | tests/rtl/tb_column_sum_buffer.sv | Shift K reference columns and recompute their complete sum |
| Single engine | rtl/sad_engine.sv | tests/rtl/tb_sad_engine.sv | Retain raw pixel columns and recompute the full K×K pixel SAD |
| Comparator tree | rtl/comparator_tree.sv | tests/rtl/tb_comparator_tree.sv | Serial minimum of valid input candidates, including tie ID |
| Right shift | rtl/right_column_shift.sv | tests/rtl/tb_right_column_shift.sv | Index an append-only log of accepted columns; no reference shift chain |

No scoreboard reads DUT internal state. Expected values use wider software-style arithmetic rather than the hardware's running recurrence. Every clock checks output validity and output data, including held invalid data and reset/clear behavior. Scoreboards sample after nonblocking updates, avoiding clock-edge races. A mismatch or timeout exits nonzero.

The original Python/deque buffer regression is preserved separately in `scripts/run_buffer_vectors.py`; it generates vectors and a bench under `build/legacy-buffer/`.

## Run commands

From the repository root:

```sh
python scripts/run_tests.py                         # all suites, 54 cases
python scripts/run_tests.py --suite column          # calculator alone
python scripts/run_tests.py --suite buffer          # column-history buffer alone
python scripts/run_tests.py --suite row             # circular row buffer alone
python scripts/run_tests.py --suite engine          # integrated lane
python scripts/run_tests.py --suite comparator      # standalone 1–32-lane tree
python scripts/run_tests.py --suite shift           # whole-column right cache
python scripts/run_tests.py --suite legacy          # original Python/deque cases
python scripts/check_walkthrough.py                 # all embedded RTL snapshots
python scripts/check_test_sensitivity.py            # deliberately wrong RTL must fail
```

Calculator, column-history and engine suites use `(K,P) = (1,8), (2,8), (3,8), (5,8), (11,8), (16,8), (11,10), (3,1)`.

The row suite uses its own widths: `(K,P,W) = (1,8,1), (2,8,3), (3,8,4), (5,8,2), (11,8,8), (16,8,5), (11,10,7), (3,1,6)`. Default module width remains 640; simulation does not stream a full 640×480 frame.

Three engine-stage suites, row buffer, comparator and right shift each run eight cases; plus six legacy cases = 54 cases. Standalone benches run directed cases plus 2000 pseudorandom input cycles by default; legacy cases retain 5000 random cycles each. Random generators are deterministic xorshift32; each bench has its own default seed. Use a nonzero `--seed` to reproduce another run. `--case K:P:W` sets row width; `--case K:P:T` sets shift taps (K:P defaults to 32 taps in the shift-only suite); for the comparator use `--case LANES:SAD_W`.

Shift matrix `(K,P,T)`: (1,1,1), (1,8,3), (3,8,1), (3,8,5), (11,8,32), (11,10,7), (16,8,2), (3,1,4).

## Waveforms

```sh
python scripts/run_tests.py --suite engine --case 11:8 --vcd
python scripts/run_tests.py --suite comparator --case 32:15 --vcd
python scripts/run_tests.py --suite shift --case 11:8:32 --vcd
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

The optional sensitivity script mutates only disposable copies under `build/mutation-checks/`. It requires ten faulty designs to compile but fail their numerical/timing scoreboards: missing pixel, early valid, ignored clear, miswired engine valid, shifted row tap, reversed comparator tie, invalid-lane win, shift-on-pause, premature tap validity and ignored shift clear. This is a targeted sanity check on the tests, not exhaustive mutation or formal coverage.

## Not covered by this milestone

Image-memory addressing, stereo row-buffer integration, left/right alignment, full image-border policy, bank-to-tree wiring, cross-group best merge, Avalon wait states, CDC, physical FPGA pins, actual Fmax, Nios V execution and full disparity-map accuracy remain later integration tests. Standalone right-tap warmup and winner/tie behavior are tested here.
