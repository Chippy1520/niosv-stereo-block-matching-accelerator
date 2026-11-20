# Row-buffer synthesis evidence

## Current row-storage review — 14 November 2026

The actual default `circular_row_buffer` now passes Quartus Prime Lite 22.1 Analysis & Synthesis for `K=11`, `PIXEL_W=8`, `IMG_W=640` on EP4CE115F29C7. It instantiates independently tested `row_ram_bank` modules. RAM reads, newest-pixel bypass and captured bank tag update on the same accepted edge, preserving the external timing contract.

| Measured item | Result |
|---|---:|
| Logic elements / combinational functions | 697 |
| Registers | 33 |
| Logical memory bits | 56,320 |
| M9K RAM nodes in Analysis & Synthesis RAM Summary | 11 |
| Each RAM node | Simple Dual Port, 640×8 per port, 5120 logical bits |
| Isolated guard elapsed time | 25.02 seconds |
| Isolated guard errors / warnings | 0 / 1 |

The one warning is (12473): the guard requests one processor although ten are available. It is not a RAM-inference warning. The RAM Summary records `READ_DURING_WRITE_MODE_MIXED_PORTS=DONT_CARE`; the parent never selects the written bank's result and uses its registered newest pixel instead.

Reproduce with `python scripts/check_row_buffer_synthesis.py --quartus-map C:/intelFPGA_lite/22.1std/quartus/bin64/quartus_map.exe`. This snapshots both RTL files into an isolated build directory, records their SHA-256 hashes and actual logs/reports, rejects timeout/tool failure/logic-only storage, and requires the expected memory bits and M9K RAM nodes. The first successful run's evidence is `build/row-buffer-synthesis/k11_p8_w640_0btjrwkj/evidence.json`; the latest rerun is in `build/row-buffer-synthesis/latest.json`.

`Stereo_SAD_RowBuffer.qsf` now targets the real 640-wide module and includes the bank dependency, not the old width-16 wrapper. The unchanged smoke-wrapper source is retained only as a historical exception.

### What made the difference

In controlled local experiments, synchronous arrays declared within the generated row implementation still mapped to logic: a K=2, width=640 candidate used 18,451 logic elements and zero memory bits. Adding raw bank-output visibility, moving the array declaration, or making reads unconditional did not establish inference. Encapsulating the same small RAM template in a bank module produced 10,240 memory bits and 52 logic elements at K=2. The final K=11 result above is the real production-width check. This is evidence for this design/tool configuration, not a universal claim that Quartus cannot infer generated memories.

### Functional and review evidence

- Eight standalone bank cases, then ten row cases including 640×480 and 641×480 raster streams, pass before full regression.
- All 80 regression cases and 16 targeted production-fault checks pass. The bank bench ignores unspecified write-edge data; the parent scoreboard reconstructs columns independently from original pixels and checks consumer-edge stability.
- Current native Questa compilation passes. Fresh native simulation is blocked by the existing one-session node-locked license holder; no user process was closed, and no fresh native simulation pass is claimed.
- Exact-source walkthroughs: [[Row RAM Bank]] and [[Circular Row Buffer]]. **Await user review before another block or publishing. Controller last.**

This closes the standalone row-storage simulation and embedded-memory mapping gate, **not** dual-image integration, fitting, physical M9K placement/count, timing closure, fMAX, sustained throughput, Nios V integration or board success. Logical memory bits are not the total physical capacity reserved by M9K blocks.

## Historical pre-repair baseline

Before this repair, Analysis & Synthesis of the `IMG_W=640` default was stopped after 300 seconds with no completion. A second attempt after removing inferred dividers also did not finish within 240 seconds.

The earlier checked project therefore used top `circular_row_buffer_synth`, instantiating `K=11`, `PIXEL_W=8`, `IMG_W=16`. Its command below now targets the repaired full-width project; the following summary is preserved from the older revision.

```sh
quartus_map Stereo_SAD_RowBuffer --read_settings_files=on --write_settings_files=off
```

Final tool result: **Analysis & Synthesis successful, 0 errors, 0 warnings**. No divider megafunctions were inferred. Memory bits reported: 0. The column readout stayed in logic cells.

Actual `.map.summary`:

```text
Analysis & Synthesis Status : Successful - Sat Sep 26 14:33:02 2026
Quartus Prime Version : 22.1std.0 Build 915 10/25/2022 SC Lite Edition
Revision Name : Stereo_SAD_RowBuffer
Top-level Entity Name : circular_row_buffer_synth
Family : Cyclone IV E
Total logic elements : 3,156
    Total combinational functions : 1,748
    Dedicated logic registers : 1,510
Total registers : 1510
Total pins : 102
Total virtual pins : 0
Total memory bits : 0
Embedded Multiplier 9-bit elements : 0
Total PLLs : 0
```

This is not a fitted resource count, not the 640-wide design, and not an Fmax. Reported pins are component ports, not DE2-115 board wiring.
