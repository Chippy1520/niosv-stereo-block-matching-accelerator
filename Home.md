# Stereo SAD FPGA — project dashboard

Board: DE2-115 / Cyclone IV. Language: SystemVerilog. Processor target: Nios V.
Assumption: grayscale pixels are 8-bit, image width 640 and height 480; confirm image orientation before integration.

## Current milestone
- [x] Implement [[Column Sum Buffer]] for one disparity lane.
- [x] Exercise RTL using independent reference vectors; see [[Verification]].
- [x] Create linked notes, graph and [[Architecture.canvas|architecture canvas]].
- [x] Quartus Analysis & Synthesis (`Stereo_SAD.qpf`, Lite 22.1).
- [ ] Fitting and fully constrained timing analysis.
- [x] Document drain → clear → restart row boundaries in [[Single SAD Engine]].
- [ ] Agree runtime configuration and future overlap/metadata requirements.
- [x] Implement [[Pipelined Column SAD Calculator]] and its standalone testbench.
- [x] Add a standalone SystemVerilog testbench for [[Column Sum Buffer]].
- [x] Integrate [[Single SAD Engine]] and verify direct raw-pixel window results.
- [x] Synthesize the engine (`Stereo_SAD_Engine.qpf`) with zero errors/warnings.
- [ ] Implement [[Image Line Buffers]] and disparity alignment.
- [ ] Integrate [[Disparity Bank]] and [[Minimum Comparator Tree]].
- [ ] Integrate [[Nios V Interface]] and board system.

## Navigate
[GitHub repository](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator) · [[docs/github-workflow|Update workflow]]

[[Column Sum Buffer - Code Walkthrough|Code, line-by-line explanation, and examples]]

[[Pipelined Column SAD Calculator]] · [[Single SAD Engine]] · [[Testbench Guide]]

[[Architecture.canvas]] · [[Rolling SAD Math]] · [[Interface Contract]] · [[Timing and Pipelining]] · [[Hardware Integration]]

The vault root is also the source project root. Open graph using Ctrl+G.
RTL: [column_sum_buffer.sv](rtl/column_sum_buffer.sv)
Test runner: [run_tests.py](scripts/run_tests.py)
No community plugins required. The calculator, buffer and single engine are implemented and independently tested. See [[Testbench Guide]]; multi-lane search and board integration remain planned.
