# Stereo SAD FPGA — project dashboard

Board: DE2-115 / Cyclone IV. Language: SystemVerilog. Processor target: Nios V.
Assumption: grayscale pixels are 8-bit, image width 640 and height 480; confirm image orientation before integration.

## Current milestone
- [x] Implement [[Column Sum Buffer]] for one disparity lane.
- [x] Exercise RTL using independent reference vectors; see [[Verification]].
- [x] Create linked notes, graph and [[Architecture.canvas|architecture canvas]].
- [x] Quartus Analysis & Synthesis (`Stereo_SAD.qpf`, Lite 22.1).
- [ ] Fitting and fully constrained timing analysis.
- [ ] Agree runtime configuration and scanline boundary protocol.
- [ ] Implement [[Image Line Buffers]], then [[Column SAD Engines]].
- [ ] Integrate [[Disparity Bank]] and [[Minimum Comparator Tree]].
- [ ] Integrate [[Nios V Interface]] and board system.

## Navigate
[GitHub repository](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator) · [[docs/github-workflow|Update workflow]]

[[Column Sum Buffer - Code Walkthrough|Code, line-by-line explanation, and examples]]

[[Architecture.canvas]] · [[Rolling SAD Math]] · [[Interface Contract]] · [[Timing and Pipelining]] · [[Hardware Integration]]

The vault root is also the source project root. Open graph using Ctrl+G.
RTL: [column_sum_buffer.sv](rtl/column_sum_buffer.sv)
Test runner: [run_tests.py](scripts/run_tests.py)
No community plugins required. Only the first RTL module is implemented; other nodes are design notes.
