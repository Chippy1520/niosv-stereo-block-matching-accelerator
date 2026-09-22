# Testbench Guide
#verified

[[Home]] · [[Pipelined Column SAD Calculator]] · [[Column Sum Buffer]] · [[Single SAD Engine]] · [[Verification]]

## Module → standalone test → integration → overall test

Each implemented module has its own tracked SystemVerilog testbench:

| Unit | RTL | Testbench | Independent reference |
|---|---|---|---|
| Column calculator | rtl/column_sad.sv | tests/rtl/tb_column_sad.sv | Serial sum of K unsigned absolute differences |
| Circular buffer | rtl/column_sum_buffer.sv | tests/rtl/tb_column_sum_buffer.sv | Shift K reference columns and recompute their complete sum |
| Single engine | rtl/sad_engine.sv | tests/rtl/tb_sad_engine.sv | Retain raw pixel columns and recompute the full K×K pixel SAD |

No scoreboard reads DUT internal state. Expected values use wider software-style arithmetic rather than the hardware's running recurrence. Every clock checks output validity and output data, including held invalid data and reset/clear behavior. Scoreboards sample after nonblocking updates, avoiding clock-edge races. A mismatch or timeout exits nonzero.

The original Python/deque buffer regression is preserved separately in `scripts/run_buffer_vectors.py`; it generates vectors and a bench under `build/legacy-buffer/`.

## Run commands

From the repository root:

```sh
python scripts/run_tests.py                         # all suites, 30 cases
python scripts/run_tests.py --suite column          # calculator alone
python scripts/run_tests.py --suite buffer          # buffer alone
python scripts/run_tests.py --suite engine          # integrated lane
python scripts/run_tests.py --suite legacy          # original Python/deque cases
python scripts/check_walkthrough.py                 # all embedded RTL snapshots
python scripts/check_test_sensitivity.py            # deliberately wrong RTL must fail
```

Standalone suite matrix: `(K,P) = (1,8), (2,8), (3,8), (5,8), (11,8), (16,8), (11,10), (3,1)`.

Three suites × eight configurations plus six legacy buffer configurations = 30 cases. Standalone benches run directed cases plus 2000 pseudorandom input cycles by default; legacy cases retain 5000 random cycles each. Random generators are deterministic xorshift32; each bench has its own default seed. Use a nonzero `--seed` to reproduce another run.

## Waveforms

```sh
python scripts/run_tests.py --suite engine --case 11:8 --vcd
```

Open `build/engine/k11_p8/waveform.vcd` in a waveform viewer. The same pattern applies to column/buffer suites. Dumping is opt-in to avoid large default artifacts. Waveforms and build files are not committed.

A tracked bench can also be run directly with Icarus, without the Python runner:

```sh
iverilog -g2012 -s tb_column_sad -o build/column_tb.vvp rtl/column_sad.sv tests/rtl/tb_column_sad.sv
vvp build/column_tb.vvp

iverilog -g2012 -s tb_column_sum_buffer -o build/buffer_tb.vvp rtl/column_sum_buffer.sv tests/rtl/tb_column_sum_buffer.sv
vvp build/buffer_tb.vvp

iverilog -g2012 -s tb_sad_engine -o build/engine_tb.vvp rtl/column_sad.sv rtl/column_sum_buffer.sv rtl/sad_engine.sv tests/rtl/tb_sad_engine.sv
vvp build/engine_tb.vvp
```

Create `build/` first if running these manually. Compiler/runtime must be on PATH. Default bench parameters are K=11, P=8; use `-Ptb_sad_engine.K=3` etc. to override. Optional vvp arguments are `+RANDOM_CYCLES=5000`, `+SEED=12345`, and `+VCD`.

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

## Testbench sensitivity

The optional sensitivity script mutates only disposable copies under `build/mutation-checks/`. It requires four faulty designs to compile but fail their numerical/timing scoreboards: missing pixel, early valid, ignored clear, and miswired engine valid. This is a targeted sanity check on the tests, not exhaustive mutation or formal coverage.

## Not covered by this milestone

Image-memory addressing, line-buffer generation, disparity alignment, image borders, winner/tie rules, Avalon wait states, CDC, physical FPGA pins, actual Fmax, Nios V execution and full disparity-map accuracy remain later integration tests.
