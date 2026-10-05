# Right-column shift cache — component synthesis

- Project: `Stereo_SAD_RightShift.qpf` / `.qsf`; top `right_column_shift`.
- Device: Cyclone IV E `EP4CE115F29C7`; Quartus Prime Lite 22.1std.0 Build 915.
- Command: `quartus_map Stereo_SAD_RightShift`.
- Defaults actually synthesized: K=11, PIXEL_W=8, TAPS=32. No reduced-width smoke wrapper.
- Analysis & Synthesis completed successfully: **0 errors, 0 warnings**.
- Reported before fitting: **2883 logic cells**, 92 input pins and 2848 output pins; elapsed 00:02:12.
- The wide tap bus is intended as internal accelerator wiring. Treating it as thousands of component-top output pins is an Analysis & Synthesis abstraction, not a physically assignable board top. No fitter, Fmax, physical I/O or board result is claimed.
- `build/right-shift-synthesis.log` and generated Quartus reports under `output_files/` are local evidence and not committed. The tracked project settings reproduce the synthesis path.

The register chain deliberately resets its payload and holds on input pauses. Left alignment, row metadata, paired frontend wiring and the lane bank remain unimplemented. These results establish component synthesis only, not end-to-end pixel throughput.
