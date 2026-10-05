# Verification workspace

## Implemented standalone benches

- `tests/rtl/tb_circular_row_buffer.sv`: flat-image column reference, warmup, ring wrap, `row_last_o`, clear and stalls.
- `tests/rtl/tb_column_sad.sv`: serial absolute-difference reference plus exact pipeline scoreboard.
- `tests/rtl/tb_column_sum_buffer.sv`: independent full-window resummation, warmup, wrapping, clear and stalls.
- `tests/rtl/tb_sad_engine.sv`: full raw-pixel window reference and row-boundary checks.
- `tests/rtl/tb_comparator_tree.sv`: serial valid-candidate minimum, deterministic tie rule, odd padding and exact pipeline scoreboard.
- `tests/rtl/tb_right_column_shift.sv`: append-only accepted-column reference, per-tap warmup, whole-column order, pauses and row-clear isolation.
- `tests/rtl/tb_left_column_delay.sv`: whole-column hold/valid, synchronous control priority, before/after-edge checks.
- `tests/rtl/tb_column_pairing.sv`: local delay/cache integration, independent accepted-column history and next-edge consumer observations.
- `tests/lab/tb_delay_lab.sv`: small seven-beat teaching baseline; separate from the production regression.

Run from the repository root:

```sh
python scripts/run_tests.py
python scripts/run_tests.py --suite column
python scripts/run_tests.py --suite buffer
python scripts/run_tests.py --suite row --case 11:8:8 --vcd
python scripts/run_tests.py --suite engine --case 11:8 --vcd
python scripts/run_tests.py --suite comparator --case 32:15 --vcd
python scripts/run_tests.py --suite shift --case 11:8:32 --vcd
python scripts/check_test_sensitivity.py
python scripts/run_testbench_lab.py --check-faults
python scripts/run_tests.py --suite delay --case 3:8 --vcd
python scripts/run_tests.py --suite pairing --case 3:8:3 --vcd
```

Start [Hands-on Testbench Lab](../Verification/Hands-on%20Testbench%20Lab.md) to write your own bench in Questa/ModelSim; `scripts/questa_lab.do` runs each existing part separately. See [Testbench Guide](../Verification/Testbench%20Guide.md) for regression commands and matrices. Seven component benches and a pairing integration bench run 64 SV configurations plus six legacy cases = 70 cases; the seven-beat teaching lab runs separately. `scripts/run_buffer_vectors.py` preserves the Python/deque reference. Every new functional RTL module needs a source walkthrough and standalone bench, checked by `scripts/check_walkthrough.py`.

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
