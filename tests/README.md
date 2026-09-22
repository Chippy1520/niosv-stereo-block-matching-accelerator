# Verification workspace

## Implemented standalone benches

- `rtl/tb_column_sad.sv`: serial absolute-difference reference plus exact pipeline scoreboard.
- `rtl/tb_column_sum_buffer.sv`: independent full-window resummation, warmup, wrapping, clear and stalls.
- `rtl/tb_sad_engine.sv`: full raw-pixel window reference and row-boundary checks.

Run from the repository root:

```sh
python scripts/run_tests.py
python scripts/run_tests.py --suite column
python scripts/run_tests.py --suite buffer
python scripts/run_tests.py --suite engine --case 11:8 --vcd
python scripts/check_test_sensitivity.py
```

See [Testbench Guide](../Testbench%20Guide.md) for compilation commands, parameters, timing, reference independence, and optional waveforms. All three benches are tracked files, not just generated snippets. `scripts/run_buffer_vectors.py` preserves the earlier independent Python/deque regression.

## Future system-level tests (not covered by the current lane)

Keep small deterministic vectors under version control rather than full external datasets.

Recommended tests:

- Single changed/matched pixel.
- Constant-disparity textured plane.
- Two regions with different disparities.
- Border and maximum-disparity cases.
- Equal-cost tie case.
- FIFO and randomized Avalon wait-state tests.
- Complete FPGA-versus-integer-reference map comparison.

Large Middlebury, Scene Flow, and KITTI files should be downloaded separately and remain outside Git.
