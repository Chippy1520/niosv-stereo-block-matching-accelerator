# Packed-load stereo frontend — verification evidence

> Historical K-only checkpoint. Its source hashes, 110-case results and utilization below are preserved, not current spare-row evidence. See [the parameterized spare-row increment](spare-row-prefetch.md) for the latest implementation and actual verification.

[[Verification]] · [[Stereo Frontend]] · [[Stereo Frontend - Code Walkthrough]] · [[Packed Circular Row Buffer]] · [[Row Word Bank]]

## Scope and verdict

**The packed-word row-store and stereo frontend datapath pass the final-source functional and synthesis gates.** This is not the complete SAD/disparity accelerator. No FIFO, ownership/refill FSM or central controller is implemented. The caller/testbench controls initialized reads, bank/word lifetime, ordered processing and row/frame boundaries.

The architectural discussion is recorded in [the council review](packed-frontend-council.md): an initial lightweight review followed by three independent read-only reviews of the earlier draft. Their conditional support for the boundaries and their protocol/coverage caveats are reconciled explicitly. Final-revision tests and synthesis are parent-run evidence, not independent reviewer reruns. Keep the shallow boundaries for this increment and stop for user review before additional blocks or publication.

## Actual checks

| Gate | Observed final-source result |
|---|---|
| `python scripts/check_walkthrough.py` | PASS: all 11 functional RTL blocks have exact-source walkthroughs and registered standalone benches |
| `python scripts/run_tests.py` | PASS: 110 cases; all original suites, eight word-bank cases, eleven packed-store cases, eleven frontend cases and six Python/deque cases |
| `python scripts/check_test_sensitivity.py` | PASS: 26 compiled deliberate faults rejected by their expected scoreboards; real RTL unchanged |
| `python scripts/run_testbench_lab.py --check-faults --examples` | PASS: seven-beat teaching baseline, two separate teaching faults and seven-module/40-edge worked examples |
| Native Questa `vlog -sv` on new RTL/dependencies/three benches | PASS, source hashes match the final files |
| Fresh native `vsim` | **BLOCKED**: exit 12, existing one-session node-locked user license; no native runtime PASS claimed, no existing session closed |
| Default packed-store Quartus Analysis & Synthesis | PASS, K=11 / P=8 / IMG_W=640, embedded M9K memory retained |
| Default stereo frontend Quartus Analysis & Synthesis | PASS, K=11 / P=8 / IMG_W=640 / TAPS=32, both row stores included |

The earlier 120-second frontend test-runner timeout was not counted as a pass. The bound is now explicit/configurable (`--timeout`, default 600 seconds), with a 20-minute CI allowance. The completed frontend cases test full row widths over a bounded number of rows, not complete 480-row frames; the standalone row-store cases cover 480 rows.

### What the new benches establish

1. `tb_row_word_bank`: whole-word writes, arbitrary independently addressed synchronous reads, burst/sequential access, same-edge different-address overlap and disabled read/write holds. It models words independently of implementation storage.
2. `tb_packed_circular_row_buffer`: raw flat-image columns, every lane and partial last words, explicit physical-bank rotation/reuse, off-tail preload, safe consumed-word overwrite overlap, independent changing read/write addresses, reset/clear write suppression, retained RAM, valid/payload bubbles and before-edge consumer checks.
3. `tb_stereo_frontend`: distinct raw left/right images, independent L/R load beats, paired read requests, direct expected `R[y,x-d]` rather than a copied shift model, per-tap horizontal warmup, matching `x/y/row_last`, row/frame clears and abort/restart. The K=11 full-width cases use **38 rows**, at W=640/T=32 and W=641/T=7. The golden schedule remains outside the DUT. A complete 480-row frontend simulation is **not** established by these results; production-default IMG_H=480 synthesis is separate evidence.

These tests do **not** prove an autonomous ownership scheduler, transport backpressure, safe arbitrary caller requests, frontend-to-engine SAD windows, reducer wiring or a complete disparity map.

## Production-width resources — final RTL

Quartus Prime Lite 22.1, Cyclone IV E `EP4CE115F29C7`, Analysis & Synthesis only:

| Top | Logic elements | Registers | Logical memory bits | M9K RAM nodes |
|---|---:|---:|---:|---:|
| `packed_circular_row_buffer` | **879** | **8** | **56,320** | **11** |
| `stereo_frontend`, 32 taps | **4,546** | **2,985** | **112,640** | **22** |

Both runs have zero errors and one warning, **12473**: single-processor execution was requested despite ten available processors. This is not an HDL or memory-inference warning. M9K *RAM nodes* are what the synthesis RAM Summary reports; no fitted physical-block utilization or timing result is inferred from them. Wide frontend ports are internal interconnect, not a proposed 3,063-pin board interface.

### Measured simplification, not an extra layer

The draft selected and rotated 32-bit words before discarding three lanes. Selecting one pixel **inside each bank's output slice first**, then rotating only the 8-bit pixels, reduced the packed store from **2,633 to 879 LE** (66.6%) and the full frontend from **8,061 to 4,546 LE**. Memory, register count, module boundaries and interface latency did not change. Full regression and fault sensitivity were rerun after applying the change. No claim of globally minimal hardware or fitted fMAX follows from this comparison.

### Reproduce

```sh
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py
python scripts/run_testbench_lab.py --check-faults --examples
python scripts/check_row_buffer_synthesis.py --top packed --quartus-map C:/intelFPGA_lite/22.1std/quartus/bin64/quartus_map.exe
python scripts/check_row_buffer_synthesis.py --top frontend --quartus-map C:/intelFPGA_lite/22.1std/quartus/bin64/quartus_map.exe
```

Small waveform cases: `--suite packed-row --case 3:8:7 --vcd` and `--suite frontend --case 3:8:9:5 --vcd`. In the existing Questa GUI use `set part packed-row` or `set part frontend`, then `do scripts/questa_lab.do`. Using the already-running GUI is the user's choice; automated checks did not commandeer it.

## Fresh ad-hoc verification refresh

The workspace guard requested a temporary OS-safe harness. `verification-script-vh7q1216.py` was created using `tempfile` under the Windows Temp directory and executed against the current workspace. It exited **0** and reported **PASS: ad-hoc verification harness completed**. It invoked all six real commands above, checked their expected output markers, validated canvas endpoints and verified that RTL, testbench and script hashes did not change during the run. This is explicitly **ad-hoc verification**, not a claim that a separate canonical CI job was run or that native Questa runtime/board validation passed. The retained machine-readable result is `build/adhoc-packed-frontend/evidence.json`, with per-command logs alongside it.

## Locally retained evidence and source binding

- `build/packed-frontend-regression.log`, `sim/results.txt`: final 110-case run.
- `build/packed-frontend-sensitivity.log`: all 26 rejected faults.
- `build/packed-frontend-teaching.log`: separate teaching checks.
- `build/packed-native/evidence.json`, compilation log and runtime license transcript: final-source native attempt.
- `build/packed-row-synthesis/latest.json`: refreshed passed packed-store run `k11_p8_w640_fbunu9_v` (28.03 seconds).
- `build/frontend-synthesis/latest.json`: refreshed passed frontend run `k11_p8_w640_mja2p54v` (63.08 seconds).
- Each synthesis JSON retains command, source hashes, dimensions, elapsed time, warnings/errors and resource/RAM evidence. The final hash comparison against every current source passed.

Key SHA-256 bindings:

| Source | SHA-256 |
|---|---|
| `rtl/row_word_bank.sv` | `710a0750ee9db98f0eacdba00d982f37f7717b6519c8abe76b10f2003d3f5fed` |
| `rtl/packed_circular_row_buffer.sv` | `15fc88e6985bafbbe1ae8c6b81f40090d9d8916616a4d6458a1000b2b6f9f46e` |
| `rtl/stereo_frontend.sv` | `5445991e31d1d6c97f51abe8523ecc0e86ce910fe8fd8b9f24f41f92f568fd2d` |

Generated build logs, tool libraries and waveforms remain local/ignored. The notes above record actual observations; no implementation was committed or published. Next review target is this frontend. The engine-bank and all controllers remain later work.
