# Progress log

## Current milestone — circular row buffer

- [x] Implement `rtl/circular_row_buffer.sv`: one raster image, a ring of K rows, registered vertical column.
- [x] Keep disparity shift, pairing, border policy and engine drain outside this module.
- [x] Add `tb_circular_row_buffer.sv`. The reference is a flat image, not a copy of the ring.
- [x] Run eight `(K,P,W)` cases, including `K=1`, `IMG_W=1`, bubbles, clear-with-valid and random traffic.
- [x] Add [[Module Blocks.canvas]] with ports, controls and interconnects. Orange blocks are not RTL.
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
