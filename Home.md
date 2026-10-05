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
- [x] Implement [[Circular Row Buffer]] — one image, K-row ring, vertical column out.
- [x] Implement and verify [[Minimum Comparator Tree]] as a standalone pipelined component; [[Minimum Comparator Tree - Code Walkthrough|read its exact code and timing]].
- [x] Implement and verify [[Right Column Shift Register]] as a standalone whole-column cache.
- [x] Implement [[Left Column Delay]] and verify local [[Column Pairing Verification|left/right pairing]].
- [x] Prepare [[Hands-on Testbench Lab]] with runnable beginner bench and tested Questa commands.
- [ ] Work through the hands-on individual-part sessions before the new top-level wrapper.
- [ ] Disparity alignment, then connect the row buffers to [[Single SAD Engine]].
- [ ] Implement [[Disparity Bank]] and connect its aligned lanes to [[Minimum Comparator Tree]].
- [ ] Integrate [[Nios V Interface]] and board system.

## Navigate
[GitHub repository](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator) · [[docs/github-workflow|Update workflow]]

**Graph spine:** [[System Architecture]] → [[Accelerator Architecture]] → [[Stereo Frontend]] / [[SAD Engine Architecture]] → [[Verification Map]]. These links create the hierarchy in Obsidian Graph; folders alone do not.

[[Column Sum Buffer - Code Walkthrough|Code, line-by-line explanation, and examples]]

[[Pipelined Column SAD Calculator]] · [[Single SAD Engine]] · [[Circular Row Buffer]] · [[Minimum Comparator Tree - Code Walkthrough]] · [[Testbench Guide]]

[[Right Column Shift Register]] — right disparity taps, validity and pause/clear timing.

[[Left Column Delay]] · [[Column Pairing Verification]] · **[[Hands-on Testbench Lab|Start the practical bench-writing session]]**

[[Architecture.canvas]] · [[Module Blocks.canvas|System blocks]] · [[Accelerator Blocks.canvas|Accelerator blocks]] · [[Stereo Frontend Blocks.canvas|Row buffers and taps]] · [[SAD Engine Blocks.canvas|One engine]] · [[Rolling SAD Math]] · [[Interface Contract]] · [[Timing and Pipelining]] · [[Hardware Integration]]

The vault root is also the source project root. Open graph using Ctrl+G.
RTL: [column_sum_buffer.sv](rtl/column_sum_buffer.sv)
Test runner: [run_tests.py](scripts/run_tests.py)
No community plugins required. The row buffer, calculator, history buffer, single engine and standalone comparator are independently tested. Open [[Module Blocks.canvas]] for the planned Nios V / shared-SDRAM / Ethernet / VGA system, then [[Accelerator Blocks.canvas]] for the accelerator's internal flow. Disparity alignment, memory transport and the multi-lane bank remain planned.
