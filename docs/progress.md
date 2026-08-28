# Progress log

## Completed

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
