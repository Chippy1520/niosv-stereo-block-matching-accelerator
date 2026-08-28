# Hardware workspace

Place the Quartus/Platform Designer project and custom RTL here.

Recommended incremental modules:

1. `stereo_ctrl_slave` — CPU-visible registers.
2. `avalon_buffer_transform` — first verified SDRAM master.
3. `stereo_burst_reader` and `stereo_burst_writer`.
4. `absdiff_lane`.
5. `sad_window_lane`.
6. `winner_take_all`.
7. `stereo_accelerator_top`.

Commit a known-good checkpoint after each integration gate. Generated Quartus directories are ignored; retain source HDL, Qsys/Qsys-script files, constraints, and reproducible build scripts.
