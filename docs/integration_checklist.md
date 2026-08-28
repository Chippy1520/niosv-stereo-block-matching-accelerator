# Nios V–accelerator integration checklist

## Preserve the baseline

- [ ] Archive the working Hello World project and bitstream.
- [ ] Record Quartus version, Nios V variant, FPGA clock, reset source, BSP settings, and address map.
- [ ] Commit the known-good state before adding SDRAM or custom IP.

## External SDRAM

- [ ] Use board-reference pin and clock assignments.
- [ ] Verify SDRAM controller reset and initialization.
- [ ] Test first/last addresses of the intended image region.
- [ ] Test multiple data patterns and address aliases.
- [ ] Test aligned and boundary-crossing blocks.

## Custom IP control slave

- [ ] Read-only identification/version register.
- [ ] Writable scratch register.
- [ ] Start/busy/done behavior.
- [ ] Error flags remain sticky until cleared.
- [ ] Configuration registers reject or flag invalid dimensions.

## Accelerator memory master

- [ ] Start with single-beat reads/writes.
- [ ] Add bursts only after correctness.
- [ ] Hold command/address stable while stalled.
- [ ] Advance counters only on accepted transfers.
- [ ] Exercise randomized wait states in simulation.
- [ ] Include input/output FIFOs to decouple memory and compute.

## Cache coherency

- [ ] Determine whether the configured Nios V data path is cached.
- [ ] Flush CPU-written input before accelerator start.
- [ ] Invalidate accelerator-written output before CPU comparison.
- [ ] Alternatively reserve an uncached SDRAM region.
- [ ] Test with changing patterns to expose stale-cache errors.

## Stereo correctness contract

- [ ] 8-bit grayscale representation defined.
- [ ] Row stride and packing defined.
- [ ] Valid output region defined.
- [ ] Border output and validity policy defined.
- [ ] SAD accumulator width derived explicitly.
- [ ] Equal-cost tie rule defined.
- [ ] Output disparity and confidence formats defined.
- [ ] CPU and RTL use identical rules.

## Benchmark fairness

- [ ] Inputs already reside in shared SDRAM before timing begins.
- [ ] CPU baseline reads/writes the same SDRAM buffers.
- [ ] Accelerator timing includes setup, memory traffic, compute, and completion.
- [ ] Display and host-file loading are excluded from both variants.
- [ ] Long batches amortize one-time overhead.
- [ ] Clock frequencies are recorded.
- [ ] Total, active, read-stall, and write-stall cycles are reported.
