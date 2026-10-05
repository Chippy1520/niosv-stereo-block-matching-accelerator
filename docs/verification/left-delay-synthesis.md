# Left-column delay — component synthesis

- Quartus Prime Lite 22.1std.0 Build 915; Cyclone IV E `EP4CE115F29C7`.
- Project `Stereo_SAD_LeftDelay.qpf/.qsf`; top `left_column_delay`, default K=11/P=8.
- Command: `quartus_map Stereo_SAD_LeftDelay`.
- Analysis & Synthesis passed: **0 errors, 0 warnings**, 90 logic cells before fitting; 92 input pins and 89 output pins reported.
- Raw local log: `build/left-delay-synthesis.log`; build output is not committed.
- This is one registered internal column/valid interface, not a board pinout.
- No fitting, I/O timing, fully constrained Fmax, row-buffer/engine/bank integration or board success is claimed.
