# Nios V software workspace

Recommended components:

- BSP/application metadata required to reproduce the build.
- Shared-SDRAM memory test.
- Accelerator driver and register definitions.
- CPU integer SAD baseline.
- Cache-maintenance helpers.
- Benchmark harness and cycle-counter access.
- Dataset loader and disparity-map exporter.

The CPU-only and accelerated paths must use identical image formats, border rules, disparity ranges, tie handling, and output formats.
