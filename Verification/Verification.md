# Verification
#verified

[[Testbench Guide]] · [[Single SAD Engine]] · [[Pipelined Column SAD Calculator]] · [[Column Sum Buffer]] · [[Circular Row Buffer]] · [[Minimum Comparator Tree - Code Walkthrough]]

## Current hierarchy of checks

Seven component self-checking SystemVerilog benches verify the row buffer, calculator, column history, single engine, comparator, [[Right Column Shift Register]] and [[Left Column Delay]]. [[Column Pairing Verification]] adds a delay/cache integration bench. The original Python/deque tests remain. See [[Testbench Guide]] and [[Hands-on Testbench Lab]].

```sh
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py
```

Default regression: **70 simulation cases**: eight SV suites × eight parameter cases, plus six Python-reference cases. SV cases have 2000 randomized cycles after directed tests; Python cases retain 5000. Twelve deliberate production-RTL faults are rejected, including pause/clear faults in the left delay. The separate teaching baseline passed seven beats and detected two compiled faults using `python scripts/run_testbench_lab.py --check-faults`.

Questa Intel Starter FPGA Edition 2021.2 actually ran the beginner baseline and all eight macro-selected component/pairing directed cases using `scripts/questa_lab.do`. Local logs are `build/lab/questa*.log`. This is functional simulation, not physical timing; CI uses Icarus and also exercises the teaching baseline/fault checks.

Local simulator: Icarus Verilog 13.0. GitHub Actions runs the same benches on Ubuntu using its packaged Icarus version. CI logs identify its installed version; the checks do not depend on matching the local version.

## Recorded evidence

- Latest local generated report: [sim/results.txt](../sim/results.txt).
- Original buffer milestone: [column-buffer-simulation.txt](../docs/verification/column-buffer-simulation.txt).
- Engine/module milestone: [single-engine-simulation.txt](../docs/verification/single-engine-simulation.txt).
- Extra-seed engine/waveform run: [single-engine-extra-seed.txt](../docs/verification/single-engine-extra-seed.txt).
- Synthesis summary: [single-engine-synthesis.md](../docs/verification/single-engine-synthesis.md).
- Comparator-only synthesis: [comparator-synthesis.md](../docs/verification/comparator-synthesis.md).
- Right-shift synthesis: [right-shift-synthesis.md](../docs/verification/right-shift-synthesis.md); full default K=11/P=8/TAPS=32, not a reduced smoke top.
- Left-delay synthesis: [left-delay-synthesis.md](../docs/verification/left-delay-synthesis.md); full default K=11/P=8, zero errors/warnings and 90 logic cells before fitting.
- GitHub Actions uploads fresh results and test artifacts for each run.

## Synthesis versus timing

Quartus Prime Lite 22.1 Analysis & Synthesis of `Stereo_SAD_Engine.qpf` passed with **zero errors and zero warnings**. Default K=11, PIXEL_W=8; post-synthesis report says **770 logic cells**, before fitting. This is not a final resource count or Fmax measurement.

The original `Stereo_SAD.qpf` buffer-only project also previously passed (one processor-count warning). Its local settings have been preserved. The history array uses asynchronous reads and maps to logic rather than inferred block RAM. The multidimensional tree produces an informational netlist-writer bus-regrouping message, not a synthesis error.

No fitting, fully constrained timing, board programming, CPU integration or physical image test has been claimed.

`Stereo_SAD_RightShift.qpf` passed Analysis & Synthesis with zero errors, zero warnings and 2883 logic cells before fitting. Its wide tap output is an internal-bus abstraction, not a board pinout. `Stereo_SAD_LeftDelay.qpf` passed with zero errors/warnings and 90 logic cells. Complete row-buffer/engine frontend integration remains separate work.

The separate default 32-lane comparator component passed Quartus Analysis & Synthesis: zero errors, one processor-count warning, 1622 logic cells before fitting. It does not demonstrate multi-engine timing or integrated winner-take-all image output.

`Stereo_SAD_RowBuffer.qpf` synthesizes an `IMG_W=16` smoke wrapper, not the functional `IMG_W=640` default. That shorter run passed with zero errors and zero warnings (3156 logic cells, zero memory bits). The 640-wide combinational readout did not finish Analysis & Synthesis within 300 seconds. See [row-buffer-synthesis.md](../docs/verification/row-buffer-synthesis.md).
