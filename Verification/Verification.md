# Verification
#verified

[[Testbench Guide]] · [[Single SAD Engine]] · [[Pipelined Column SAD Calculator]] · [[Column Sum Buffer]] · [[Circular Row Buffer]] · [[Minimum Comparator Tree - Code Walkthrough]]

## Current hierarchy of checks

Six standalone self-checking SystemVerilog benches independently verify the row buffer, calculator, circular column history, integrated engine, standalone comparator and [[Right Column Shift Register]]. The original Python/deque buffer tests are also retained. See [[Testbench Guide]] for exact files, commands, scoreboards and coverage.

```sh
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py
```

Default regression: **54 simulation cases**. Three SV suites run eight `(K,P)` configurations each, the row suite runs eight `(K,P,W)` configurations, the comparator runs eight `(LANES,SAD_W)` configurations, the right shift runs eight `(K,P,TAPS)` configurations, plus six original Python-reference cases. SV cases include 2000 randomized cycles each after directed tests; Python-reference cases include 5000 each. All output cycles are checked, not just final checksums. Ten deliberate RTL faults are rejected, including shift-on-pause, premature tap validity and ignored shift clear.

Local simulator: Icarus Verilog 13.0. GitHub Actions runs the same benches on Ubuntu using its packaged Icarus version. CI logs identify its installed version; the checks do not depend on matching the local version.

## Recorded evidence

- Latest local generated report: [sim/results.txt](../sim/results.txt).
- Original buffer milestone: [column-buffer-simulation.txt](../docs/verification/column-buffer-simulation.txt).
- Engine/module milestone: [single-engine-simulation.txt](../docs/verification/single-engine-simulation.txt).
- Extra-seed engine/waveform run: [single-engine-extra-seed.txt](../docs/verification/single-engine-extra-seed.txt).
- Synthesis summary: [single-engine-synthesis.md](../docs/verification/single-engine-synthesis.md).
- Comparator-only synthesis: [comparator-synthesis.md](../docs/verification/comparator-synthesis.md).
- Right-shift synthesis: [right-shift-synthesis.md](../docs/verification/right-shift-synthesis.md); full default K=11/P=8/TAPS=32, not a reduced smoke top.
- GitHub Actions uploads fresh results and test artifacts for each run.

## Synthesis versus timing

Quartus Prime Lite 22.1 Analysis & Synthesis of `Stereo_SAD_Engine.qpf` passed with **zero errors and zero warnings**. Default K=11, PIXEL_W=8; post-synthesis report says **770 logic cells**, before fitting. This is not a final resource count or Fmax measurement.

The original `Stereo_SAD.qpf` buffer-only project also previously passed (one processor-count warning). Its local settings have been preserved. The history array uses asynchronous reads and maps to logic rather than inferred block RAM. The multidimensional tree produces an informational netlist-writer bus-regrouping message, not a synthesis error.

No fitting, fully constrained timing, board programming, CPU integration or physical image test has been claimed.

`Stereo_SAD_RightShift.qpf` passed Analysis & Synthesis with zero errors, zero warnings and 2883 logic cells before fitting. Its thousands of top-level tap output bits are an internal-bus abstraction; this is not a physically assignable board top. The matching left delay and frontend integration remain separate work.

The separate default 32-lane comparator component passed Quartus Analysis & Synthesis: zero errors, one processor-count warning, 1622 logic cells before fitting. It does not demonstrate multi-engine timing or integrated winner-take-all image output.

`Stereo_SAD_RowBuffer.qpf` synthesizes an `IMG_W=16` smoke wrapper, not the functional `IMG_W=640` default. That shorter run passed with zero errors and zero warnings (3156 logic cells, zero memory bits). The 640-wide combinational readout did not finish Analysis & Synthesis within 300 seconds. See [row-buffer-synthesis.md](../docs/verification/row-buffer-synthesis.md).
