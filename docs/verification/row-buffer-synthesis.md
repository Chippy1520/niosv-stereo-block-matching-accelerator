# Row-buffer synthesis evidence

The functional module default is `IMG_W=640`. Quartus Prime Lite 22.1 Analysis & Synthesis of that default was stopped after 300 seconds with no completion. A second attempt after removing the inferred dividers also did not finish within 240 seconds.

The checked project therefore uses top `circular_row_buffer_synth`, which instantiates the same module at `K=11`, `PIXEL_W=8`, `IMG_W=16`.

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
