# Single-engine synthesis evidence

Tool command:

```sh
quartus_map Stereo_SAD_Engine --read_settings_files=on --write_settings_files=off
```

Final tool result: **Analysis & Synthesis successful, 0 errors, 0 warnings**. Project targets EP4CE115F29C7; RTL defaults K=11 and PIXEL_W=8.

The following is the actual generated `.map.summary` (not a fitted report):

```text
Analysis & Synthesis Status : Successful - Wed Sep 23 01:29:03 2026
Quartus Prime Version : 22.1std.0 Build 915 10/25/2022 SC Lite Edition
Revision Name : Stereo_SAD_Engine
Top-level Entity Name : sad_engine
Family : Cyclone IV E
Total logic elements : 770
    Total combinational functions : 650
    Dedicated logic registers : 368
Total registers : 368
Total pins : 196
Total virtual pins : 0
Total memory bits : 0
Embedded Multiplier 9-bit elements : 0
Total PLLs : 0
```

The reported top-level pins are component ports, not approved DE2-115 board wiring. No physical pin mapping, fitter run, final resource count, Fmax or timing closure is claimed. The provisional SDC targets 50 MHz but that is not a measured speed.

The history array's asynchronous read prevents block-RAM inference in this implementation. Quartus also reports informational inability to regroup the internal multidimensional tree into a netlist bus; synthesis succeeds.

Compatibility fix verified in this run: this Quartus Lite 22.1 parser rejected inline `for (genvar ...)`, so generate variables are declared separately. Simulation passes after that change.
