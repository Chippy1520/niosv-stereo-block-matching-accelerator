# Progress log

## Current milestone — standalone right-column shift register

- [x] Implement `rtl/right_column_shift.sv`: shift whole K-pixel columns only on accepted input; registered taps have per-disparity warmup validity.
- [x] Preserve history across pauses, suppress bubble validity, and discard simultaneous input on reset/clear. Caller clears horizontal history between output rows.
- [x] Deliver [[Right Column Shift Register]] with exact source and sectionwise syntax/timing reasons, plus `tb_right_column_shift.sv` whose reference indexes an append-only accepted-column log.
- [x] Run eight shift cases, default full regression of 54 cases, and ten fault checks. Extra K=11/P=8/TAPS=32 run: seed 12345, 10000 random cycles, 8000 valid output beats; VCD generated locally.
- [x] Quartus Lite 22.1 Analysis & Synthesis of the full default component: 0 errors, 0 warnings, 2883 logic cells before fitting. [Evidence](verification/right-shift-synthesis.md).
- [ ] Implement matching left-column/valid alignment separately, then verify frontend pairing, coordinate/border policy and upstream drain timing. No bank or board claim.

## Previous milestone — standalone comparator tree

- [x] Implement `rtl/comparator_tree.sv` with a registered valid-aware minimum reduction over explicit `(SAD, disparity)` IDs; ties choose lower disparity.
- [x] Add exact-source [[Minimum Comparator Tree - Code Walkthrough]] and independently scored `tb_comparator_tree.sv`, including one/odd/32 lanes, bubbles and clear/reset.
- [x] Run five standalone SV suites and the Python reference: 46 simulation cases. Seven deliberate RTL faults were rejected, including reversed ties and invalid-lane selection.
- [x] Quartus Lite 22.1 Analysis & Synthesis of the default 32-lane component: 0 errors, 1 processor-count warning, 1622 logic cells before fitting. [Evidence](verification/comparator-synthesis.md).
- [ ] Feed the tree aligned, border-masked scores from a multi-lane bank and carry coordinate tags; not part of this standalone module.

## Vault hierarchy and HDL-module delivery rule

- [x] Organize study notes and drill-down canvases as system → accelerator → frontend/engine → module, with linked Obsidian hub notes. Preserve the root dashboard, project files, HDL, and existing code walkthroughs.
- [x] Update the note map and relative links; check wiki/Markdown targets and canvas file/edge references after relocation.
- [x] Require every new functional RTL module to register its exact-code walkthrough and standalone self-checking bench in the test runner. The existing synthesis-only smoke wrapper remains an explicit exception.
- [x] Run the 38-case RTL regression and five deliberate-fault checks; confirm an unregistered new RTL file is rejected.

## Previous documentation milestone — calculator, engine, and both circular buffers

- [x] Add code-adjacent explanations and Obsidian-rendered diagrams to [[Pipelined Column SAD Calculator]], [[Single SAD Engine]], [[Circular Row Buffer]], and [[Column Sum Buffer - Code Walkthrough]].
- [x] Distinguish the image-row ring from the per-engine column-history ring; document valid/bubble propagation, warmup, row drain, and stage boundaries.
- [x] Verify embedded RTL snapshots, the complete simulation regression, and deliberate-fault detection. This is documentation only; no new board/timing claim.

## Current milestone — circular row buffer

- [x] Implement `rtl/circular_row_buffer.sv`: one raster image, a ring of K rows, registered vertical column.
- [x] Keep disparity shift, pairing, border policy and engine drain outside this module.
- [x] Add `tb_circular_row_buffer.sv`. The reference is a flat image, not a copy of the ring.
- [x] Run eight `(K,P,W)` cases, including `K=1`, `IMG_W=1`, bubbles, clear-with-valid and random traffic.
- [x] Add the component-level canvas (subsequently split into system-level [[Module Blocks.canvas]] and [[Accelerator Blocks.canvas]] / [[Stereo Frontend Blocks.canvas]] drill-downs). Orange stages remain planned, not RTL.
- [ ] Connect two instances through a disparity tap and row-drain controller. Not this milestone.
- [x] Quartus smoke synthesis of `circular_row_buffer_synth` (`IMG_W=16`): 0 errors, 0 warnings, 3156 logic cells before fitting. The `IMG_W=640` default did not finish Analysis & Synthesis within 300 seconds.

## Previous milestone — pipelined calculator and single engine

- [x] Implement `rtl/column_sad.sv` with registered differences and balanced pipelined column reduction.
- [x] Add tracked standalone `tb_column_sad.sv` and `tb_column_sum_buffer.sv`.
- [x] Integrate `rtl/sad_engine.sv`; `tb_sad_engine.sv` independently recomputes full raw-pixel window SADs.
- [x] Run eight configurations for each standalone SV bench plus six original Python-reference cases (30 total).
- [x] Verify exact pipeline delay, bubbles, reset/clear priority, flushes, row drain/counts and no cross-row history.
- [x] Detect four deliberately introduced faults using the new benches.
- [x] Run an additional K=11/P=8 engine test with seed 12345, 5000 randomized cycles and VCD output.
- [x] Synthesize `Stereo_SAD_Engine.qpf` in Quartus Lite 22.1: zero errors, zero warnings, 770 logic elements before fitting.
- [x] Update study notes, source snapshots, architecture canvas and GitHub CI.

Evidence: [module/engine regression](verification/single-engine-simulation.txt), [extra seed](verification/single-engine-extra-seed.txt), [synthesis](verification/single-engine-synthesis.md).

No image-stream line buffer, disparity shifter, multi-lane bank, fitted Fmax or board integration is claimed.

## Previous component milestone — circular column history

- [x] Implement parameterized `rtl/column_sum_buffer.sv` for one disparity lane.
- [x] Verify six parameter configurations using Icarus Verilog 13.0 against an independent deque reference.
- [x] Verify warmup, wraps, bubbles, maximum/zero inputs, reset, clear and randomized traffic.
- [x] Add `Stereo_SAD.qpf` / `.qsf` for EP4CE115F29C7 and a provisional 50 MHz constraint.
- [x] Quartus Prime Lite 22.1 Analysis & Synthesis passed: zero errors, one processor-count warning. No fitted Fmax claimed.
- [x] Add the Obsidian dashboard, architecture canvas, interface notes and full code walkthrough.
- [x] Preserve prior repository history, system reports and diagram sources while making the working component the main entry point.
- [x] Add push/PR CI for simulation and embedded-source consistency.
- [x] Implement upstream column absolute differences and adder tree (completed in engine milestone).
- [x] Integrate one supplied-alignment SAD lane.
- [x] Implement the circular row-buffer abstraction (`rtl/circular_row_buffer.sv`). Disparity alignment is still open.
- [ ] Integrate parallel lanes and winner-take-all tree.

Evidence: [component simulation output](verification/column-buffer-simulation.txt), [test runner](../scripts/run_tests.py), [RTL](../rtl/column_sum_buffer.sv).

The component tests verify column-sum history, not raw-image stereo matching, CPU integration or board operation. The separate system-integration gates below remain open.

## Prior board bring-up (recorded before the component milestone)

- [x] Nios V processor instantiated for the DE2-115 project.
- [x] FPGA programming flow operational.
- [x] Nios V software build/download flow operational.
- [x] `Hello World` executed successfully.
- [x] JTAG UART output observed.

## Interpretation

This confirms the processor, clock/reset path, basic memory used by the application, BSP/application build, debugger/download path, and JTAG UART. It does **not yet prove external SDRAM sharing with a custom accelerator**.

## Immediate gate

- [ ] Verify CPU external-SDRAM read/write operation.
- [ ] Run walking-bit, address-pattern, and burst-sized memory tests.
- [ ] Add a custom accelerator control slave.
- [ ] Add a custom memory master.
- [ ] CPU writes a known input array to SDRAM.
- [ ] Accelerator reads, transforms, and writes it to another SDRAM region.
- [ ] CPU verifies every output word.
- [ ] Confirm cache flush/invalidate or use uncached buffers.
- [ ] Record total, active, read-stall, and write-stall cycles.

## Stereo milestones

- [ ] Freeze pixel format, border policy, tie rule, window size, and disparity range.
- [ ] Complete PC integer SAD reference.
- [ ] Generate tiny exact-disparity synthetic vectors.
- [x] Verify one supplied-alignment disparity lane in RTL simulation; pixel-column frontend still pending.
- [ ] Verify full winner-take-all output.
- [ ] Run one Middlebury pair end to end.
- [ ] Synthesize multiple disparity-lane configurations.
- [ ] Measure CPU-only and accelerated end-to-end cycles.
- [ ] Demonstrate continuous stored stereo pairs.
