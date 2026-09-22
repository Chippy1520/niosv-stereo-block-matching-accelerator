# Progress log

## Current component milestone — circular column history

- [x] Implement parameterized `rtl/column_sum_buffer.sv` for one disparity lane.
- [x] Verify six parameter configurations using Icarus Verilog 13.0 against an independent deque reference.
- [x] Verify warmup, wraps, bubbles, maximum/zero inputs, reset, clear and randomized traffic.
- [x] Add `Stereo_SAD.qpf` / `.qsf` for EP4CE115F29C7 and a provisional 50 MHz constraint.
- [x] Quartus Prime Lite 22.1 Analysis & Synthesis passed: zero errors, one processor-count warning. No fitted Fmax claimed.
- [x] Add the Obsidian dashboard, architecture canvas, interface notes and full code walkthrough.
- [x] Preserve prior repository history, system reports and diagram sources while making the working component the main entry point.
- [x] Add push/PR CI for simulation and embedded-source consistency.
- [ ] Implement upstream column absolute differences and adder tree.
- [ ] Integrate a complete disparity lane and image line buffers.
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
- [ ] Verify one disparity lane in RTL simulation.
- [ ] Verify full winner-take-all output.
- [ ] Run one Middlebury pair end to end.
- [ ] Synthesize multiple disparity-lane configurations.
- [ ] Measure CPU-only and accelerated end-to-end cycles.
- [ ] Demonstrate continuous stored stereo pairs.
