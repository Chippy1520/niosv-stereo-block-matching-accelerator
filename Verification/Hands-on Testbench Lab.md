# Hands-on Testbench Lab

[[Home]] → [[Verification Map]] → this hands-on session. References: [[Testbench Guide]], [[Left Column Delay]], [[Right Column Shift Register]], [[Column Pairing Verification]].

> **Goal:** you write and understand a self-checking bench, not just press Run on someone else's tests. Start with a one-byte delay, then test every existing component separately. Only after these checkpoints do we start the frontend/bank/top-level wrapper. This guide is preparation; completing it is your learning session, not something CI can do for you.

## Learning route

| Session | Build / experiment | Finish with |
|---|---|---|
| 1 | Left delay: DUT, clock, reset, directed stimulus, assertions, waveform | A tiny bench you can explain line by line |
| 2 | Right taps and image row buffer | Separate horizontal history from vertical history; prove pause and warmup |
| 3 | Column SAD, column-history buffer, comparator | Independent arithmetic references, width limits, pipeline scoreboards |
| 4 | Existing single engine and column pairing | Prove wiring/timing from original inputs, then prepare the wrapper contract |

Do one session at a time. Keep predictions, actual traces and failure explanations beside the relevant module note. No slides or extra Obsidian plugins are needed.

## 0. Safe workspace and two ways to run

Golden RTL lives in `rtl/`; golden self-checking benches in `tests/rtl/`. The smaller teaching baseline is `tests/lab/tb_delay_lab.sv`. Put your experiments under ignored `build/`, not over the production RTL. Keep the original module name `tb_delay_lab` in your first working copy.

### Questa/ModelSim — primary hands-on path

Open Questa. In its **Transcript**, change to your real repository path (replace the example):

```tcl
cd {C:/path/to/Stereo-SAD-FPGA}
set root [pwd]
set part lab
do scripts/questa_lab.do
```

The helper compiles the DUT and bench with `vlog -sv`, creates a local `work` library and `modelsim.ini` below `build/questa_lab/`, loads the bench with signal visibility, adds waves, and runs directed tests. It leaves the simulation open at `$finish`; **a stopped simulation is not automatically a pass**. Look for `PASS delay lab: 7 directed beats` and no assertion failure.

The macro changes directory into its build folder. For subsequent runs use the saved absolute root:

```tcl
set part shift
do "$root/scripts/questa_lab.do"
```

Create your own bench copy in the Transcript:

```tcl
file mkdir "$root/build"
file copy -force "$root/tests/lab/tb_delay_lab.sv" "$root/build/my_delay_lab.sv"
set student_bench "$root/build/my_delay_lab.sv"
set part lab
do "$root/scripts/questa_lab.do"
```

Edit that copy with your code editor and rerun the macro after every change. It recompiles; `restart` alone would reuse stale compiled code. When returning to golden tests:

```tcl
unset -nocomplain student_bench student_rtl
```

If the macro reports a missing repository, fix `root`; do not change the RTL to fix a path error. Questa's `do` macro context does not reliably make `info script` the user .do path, so this helper explicitly uses your repository root.

### Portable Icarus — reproducible command-line fallback

From a shell at the repository root:

```sh
python scripts/run_testbench_lab.py
python scripts/run_testbench_lab.py --check-faults
```

The good trace and waveform are `build/lab/reference.log` and `build/lab/reference.vcd`. `--check-faults` changes only disposable DUT copies, verifies that they compile and fail the teaching scoreboard, and leaves real RTL untouched. The good waveform is preserved separately from fault-run waveforms.

## 1. First write the contract, not the stimulus

For K=1 / PIXEL_W=8 the left delay input and output are each one byte. A rising edge accepts data only when reset is released, clear is zero and input valid is one.

Before running anything, fill in this expected table in your notes:

| Stimulus at edge | Expected output valid | Expected byte |
|---|---|---|
| reset with valid ff | 0 | 00 |
| accepted 12 | 1 | 12 |
| accepted a5 | 1 | a5 |
| invalid input ff | 0 | a5 |
| clear with valid ff | 0 | 00 |
| accepted 3c after clear | 1 | 3c |
| reset and clear with valid ff | 0 | 00 |

Cover reset, ordinary input, consecutive inputs, pauses, control priority and restart. Random traffic is useful **after** these directed cases; it is not a replacement for knowing what should happen.

## 2. Build the shell yourself

In a new scratch file, write these pieces before looking at the full reference bench:

```systemverilog
`timescale 1ns/1ps
module tb_delay_lab;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear_i = 0, valid_i = 0;
    logic [7:0] column_i = '0;
    wire valid_o;
    wire [7:0] column_o;
    left_column_delay #(.K(1), .PIXEL_W(8)) dut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i), .valid_i(valid_i),
        .column_i(column_i), .valid_o(valid_o), .column_o(column_o)
    );
endmodule
```

| Syntax | What you are doing |
|---|---|
| `module tb_delay_lab;` | A simulation top with no physical ports |
| `logic` inputs | Variables the bench drives; not physical pins |
| `wire` outputs | Connections driven by the DUT |
| `#(...)` | Choose elaboration-time DUT parameters; here one eight-bit pixel |
| `.port(signal)` | Explicit named connection; easier to audit than positional wiring |
| `always #5` | Simulation-only clock: toggle every 5 ns; never synthesize this bench |
| `initial` | A concurrent simulation process that starts once |

The checked-in reference uses `(.*)` because its local signal names exactly match the ports; write the explicit names first so you understand every connection. Add an `initial` sequence and `$finish`; otherwise your clock runs forever. Then add a watchdog so a missing `$finish` or stuck task becomes a failure.

**Your change:** rename one signal in your scratch bench and reconnect it explicitly. Compile. A typo should produce a compiler error, not an invented implicit one-bit net; add `default_nettype none` as in the reference.

## 3. Drive before the edge; check after the edge

The production DUT uses `always_ff @(posedge clk)` and nonblocking assignments. Use this bench timing:

```systemverilog
@(negedge clk);
valid_i = 1;
column_i = 8'h12;
@(posedge clk);
#1;
if (valid_o !== 1'b1 || column_o !== 8'h12)
    $fatal(1, "Expected accepted byte 12");
```

- Drive on the falling edge: inputs are stable before the sampling edge.
- The DUT samples at the next rising edge.
- Nonblocking updates occur later in that simulation time slot.
- `#1` waits past those updates before the bench checks new outputs. It is **not** an extra hardware register or a real timing measurement.
- `!==` treats X/Z as a mismatch; plain `!=` can produce X and let an `if` silently skip failure.
- `$fatal(1, ...)` makes a failed check visible; `$display` alone cannot certify a pass.

**Experiment:** temporarily remove `#1` in your scratch bench. Explain the old-value observation. Restore it. Do not fix this race by arbitrarily changing the RTL clock edge.

The delay bench also checks output stability after changing inputs but **before** the rising edge. That catches accidental combinational pass-through and asynchronous reset behavior.

## 4. Factor a beat task; make every beat self-checking

Read `tests/lab/tb_delay_lab.sv` now. Its `beat(rn,cl,en,data,want_valid,want_data)` task:

1. Drives one input event on a falling edge.
2. Waits for the next rising edge and NBA settlement.
3. Prints stimulus and actual output.
4. Compares against your explicit expected valid/data.
5. Increments a checked-beat counter only after success.

`task automatic` gives each call its own local arguments. `input bit` is appropriate for deliberate two-state controls; `logic [7:0]` carries payload. This task is a testing helper, not another hardware module.

**Your change:** add an extra pause with a different input byte and an extra valid byte after it. Predict the held output during both pauses. Update the expected arguments, run, and make the final checked count match your new sequence. Deliberately put a wrong expected byte in one call; require a failure before restoring it.

Reference baseline observed in both Icarus and Questa:

```text
out_valid=0 out=00   reset
out_valid=1 out=12   accepted input
out_valid=1 out=a5   consecutive input
out_valid=0 out=a5   pause: held payload
out_valid=0 out=00   clear wins over valid
out_valid=1 out=3c   clean restart
out_valid=0 out=00   reset and clear
PASS delay lab: 7 directed beats
```

The real `$time` trace may print 16000 for the first observation: with this precision that is 16000 ps = 16 ns. Compare units, not just the displayed integer.

## 5. Look at the waveform with a purpose

In Questa inspect `clk`, `rst_n`, `clear_i`, `valid_i`, `column_i`, `valid_o`, `column_o`. Select hex for bytes. Zoom around an accepted input, a pause, and clear-with-valid. Explain each transition using the contract, not merely the picture.

- A new byte appears **after** its sampling edge, not when you first drive the input.
- Valid follows the registered beat, not combinational input changes.
- Held data during a pause is not a second accepted output.
- Reset here is synchronous; toggling reset between edges must not immediately change the register.

**Checkpoint:** capture or sketch these three windows and annotate the sampling edge. You should be able to explain why a downstream register sees the previous output at the same rising edge. A waveform complements assertions; it does not replace them.

## 6. Prove that your bench can catch a real bug

Do not damage `rtl/left_column_delay.sv`. Make a scratch DUT copy:

```tcl
file copy -force "$root/rtl/left_column_delay.sv" "$root/build/my_left_column_delay.sv"
set student_rtl "$root/build/my_left_column_delay.sv"
set part lab
do "$root/scripts/questa_lab.do"
```

Keep the module name `left_column_delay`. In the copy, make **one fault at a time**:

1. Change `valid_o <= valid_i;` to `valid_o <= 1'b1;`. The invalid beat must fail.
2. Restore it. Remove `|| clear_i` from the reset/clear condition. Clear-with-valid must fail.
3. Restore it. Remove the `if (valid_i)` payload enable. A pause with changing input must fail.

Require a successful compile followed by a numerical/control assertion failure; a syntax error is not proof of test sensitivity. Run the golden tests again after restoring the copy. `unset -nocomplain student_rtl student_bench` returns to the reference.

The scripted Icarus lab verifies the first two faults automatically. The full sensitivity runner covers additional modules; its mutants live under ignored `build/mutation-checks/`.

## 7. Replace hard-coded expected arguments with a reference model

Use `tests/rtl/tb_left_column_delay.sv` only after your directed bench works. Before copying it, implement your own expected byte and valid:

```text
on a sampled edge:
  if reset or clear: expected byte = 0; expected valid = 0
  else:
    expected valid = sampled input valid
    if accepted: expected byte = sampled input byte
compare registered DUT outputs after NBA settlement
```

This is the independent behavioral contract for a one-register delay. Never set expected data from `dut.column_o`, or read internal registers to decide what should happen. That would make the test agree with the same bug.

Then add deterministic randomized traffic with a fixed seed, a check counter, a timeout, and a failure report with case/edge/input/expected/actual. Keep the directed cases. Expand to K=3 and walk a nonzero value through every packed row slice `[row*P +: P]`.

## 8. Test each existing part separately

For the golden module bench in Questa, set `part` from this table and run `do "$root/scripts/questa_lab.do"`. The macro uses small directed configurations: K=3/P=8, row width 4, three shift taps, or three comparator lanes. These are teaching settings, not performance evidence.

| Part | Study note / bench | Write this independent reference or exercise |
|---|---|---|
| `delay` | [[Left Column Delay]] / `tb_left_column_delay.sv` | Expected byte/valid; pre-edge hold; change one packed row at a time |
| `shift` | [[Right Column Shift Register]] / `tb_right_column_shift.sv` | Append accepted columns to a log; tap d indexes count−1−d; don't copy a shift chain |
| `row` | [[Circular Row Buffer]] / `tb_circular_row_buffer.sv` | Keep an original flat image; reconstruct each vertical column from image coordinates, not the DUT ring |
| `column` | [[Pipelined Column SAD Calculator]] / `tb_column_sad.sv` | Serial sum of unsigned absolute differences; enqueue expected values with due edges |
| `buffer` | [[Column Sum Buffer - Code Walkthrough]] / `tb_column_sum_buffer.sv` | Recompute the complete K-column sum; don't reuse the DUT running-sum recurrence |
| `comparator` | [[Minimum Comparator Tree - Code Walkthrough]] / `tb_comparator_tree.sv` | Scan only valid candidates; minimize cost, then disparity ID; no reference reduction tree |
| `engine` | [[Single SAD Engine]] / `tb_sad_engine.sv` | Recompute K×K SAD directly from original pixel columns; verify row drain and restart |
| `pairing` | [[Column Pairing Verification]] / `tb_column_pairing.sv` | Compare L[x] and R[x−d] and masks after registration and before the next consumer edge |

For each part: start with a reset and a short deterministic sequence, insert a pause with changing inputs, test clear-with-valid, exercise its smallest legal parameters, then add random traffic. Write your own scratch bench before reading the complete golden scoreboard. Do not assume all blocks' latency or warmup is the same.

### Concrete mini-experiments and expected results

- **Right shift, T=3:** accept A, B, pause, C. Predict columns A/empty/empty, B/A/empty, held B/A/empty, C/B/A; masks 001, 011, 000, 111. Clear, then accept D: no old-row tap may remain valid.
- **Row buffer, K=3/W=4:** stream rows `[1,2,3,4]`, `[5,6,7,8]`, `[9,10,11,12]`. First complete columns are `[1,5,9]`, `[2,6,10]`, `[3,7,11]`, `[4,8,12]` in oldest-to-newest row order. `row_last_o` is true on the final complete-column position. Pause must not advance x. Row clear here is a new image/reset operation: don't clear vertical history at each normal row end.
- **Column SAD, K=3:** left `[10,50,200]`, right `[20,30,100]` gives **130**. Swap sides: same sum. Change each pixel independently. Check the expected output at edge t+2 after input edge t, not immediately.
- **Column history, K=3:** input costs 6,15,24,33 give valid windows **45**, then **72**. First two accepted costs are warmup. Insert an invalid beat before 24: history must not advance. Clear, then require warmup again.
- **Comparator, three lanes:** costs `[30,5,5]`, IDs `[7,9,2]`, all valid → `(5,2)`. Replace the first cost by zero but invalidate that lane: it must not win. Physical lane index is not the disparity ID. Tie handling is not “take the first lane”.
- **Engine, K=3:** left columns `[1,2,3]`, `[4,5,6]`, `[7,8,9]` against zero columns give first window **45**. Its due edge is t+3 relative to the third accepted engine input. Drain three invalid-input edges before clear on a separate edge. Clearing immediately would abort pending output.
- **Pairing:** create distinct left/right patterns; verify the left is current x for every active right tap, not L[x−d]. At a consumer edge check the old registered beat before NBA updates. Inspect [[Column Pairing Verification]] for the row-clear scope.

For the calculator/comparator/engine, maintain a due-edge queue: enqueue value + valid at acceptance, advance the edge counter even during bubbles, compare when due, and clear pending expectations when clear aborts the pipeline. Warmup counts **accepted columns**; pipeline latency counts **clock edges**. Confusing these is a common reason a scoreboard looks right under continuous traffic but fails on pauses.

### Portable individual commands

```sh
python scripts/run_tests.py --suite delay --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite shift --case 3:8:3 --random-cycles 0 --vcd
python scripts/run_tests.py --suite row --case 3:8:4 --random-cycles 0 --vcd
python scripts/run_tests.py --suite column --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite buffer --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite comparator --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite engine --case 3:8 --random-cycles 0 --vcd
python scripts/run_tests.py --suite pairing --case 3:8:3 --random-cycles 0 --vcd
```

These commands run golden benches, not your scratch bench. For your own bench use the Questa override or compile it explicitly with Icarus. Examples of golden waveform folders: `build/delay/k3_p8/`, `build/shift/k3_p8_t3/`, `build/row/k3_p8_w4/`, `build/comparator/n3_sad8/`, `build/pairing/k3_p8_t3/`; each contains `waveform.vcd` when `--vcd` is used.

After directed tests, rerun one case with `--seed 12345 --random-cycles 10000`. The same seed and parameters reproduce the same bench traffic. A different simulator can evaluate random function calls in arguments in a different order; compare each run to its reference, not different simulators' random-cycle counters.

## 9. Debug a failure in this order

1. Did it compile? Port/width/module-name problems are not arithmetic failures.
2. Find the **first** failed edge and print stimulus, expected valid/data and actual valid/data.
3. Was the scoreboard sampling before NBA updates by mistake?
4. Was this accepted-column warmup, a pipeline bubble, reset, or clear?
5. Check packed row/tap ordering and unsigned widths.
6. Confirm that the expected model does not reuse the DUT's recurrence or internal state.
7. Save the failing seed/case and shorten it into a directed regression before fixing the RTL.

Do not add random `#` delays until the failure disappears; model the actual sampling contract. Do not weaken an assertion to silence an unknown value.

## 10. Completion gate before the new wrapper

- [ ] I wrote a scratch self-checking delay bench and can explain every line.
- [ ] I predicted the pause/clear/reset trace and checked it in a waveform.
- [ ] My bench rejected at least one compiled, deliberately broken DUT.
- [ ] I tested the row store, shift, calculator, history buffer and comparator separately.
- [ ] I can explain accepted-position warmup versus edge-based pipeline latency.
- [ ] My engine reference starts from raw pixels, not partial DUT outputs.
- [ ] I understand why left/right pairing has both post-edge and consumer-edge checks.
- [ ] We have agreed coordinate/border validity, metadata alignment, and drain → clear → restart at the intended wrapper boundary.

Bring your first scratch bench or a waveform/failure to our hands-on session; we can work through one part at a time. The controller, row-buffer assembly, multi-lane bank, coordinate tags, reducer wiring, memory transport and board integration remain explicitly unimplemented. Passing this lab does not complete those blocks.

## Preparation evidence, not a claim that you completed the lesson

The teaching baseline's seven directed beats and all eight macro-selected component/pairing simulations were actually exercised in Questa Intel Starter FPGA Edition 2021.2. Icarus ran the baseline and fault checks as well. The full regression and sensitivity checks are recorded in [[Verification]]. No GUI screenshot approval, fitted timing or board behavior is inferred from simulation.
