# Control Emulation

[[Verification]] · [[Integration Readiness]] · [[Stereo SAD Datapath]] · [[Project Plan]]

## Test contract

Simulation-only control emulation drives the **real `stereo_sad_datapath`**, not a mocked frontend or backend. No synthesizable controller, bus master, FIFO or functional RTL module is added. The existing direct-stimulus raw-window bench remains a separate regression.

### Lightweight council, before implementation

- **Advocate:** exercise loading, readiness, ring reuse, row scheduling and result consumption together at the actual top-level ports.
- **Skeptic:** a scheduler checking its own counters could validate an unsafe schedule. Keep separate accepted-port word/owner tracking, a full raw-image oracle and an independently checked result sink.
- **Evidence:** the existing `stereo_raw_checks.svh` computes full raw-pixel costs, but normal whole-path prefetch supplies future L/R words together. It does not implement an independently delayed completion-gated frame scheduler.
- **Feasibility / verdict:** proceed with one parameterized SV bench and compiled fault checks. Preserve the current hardware contract and all existing benches; do not build an RTL controller merely to test the datapath.

## Controller obligations

| Phase | Required behavior |
|---|---|
| Load / wait | Independently stalled L/R word arrivals share one bank/word address. Track each side separately, including the final partial word. Never start a window until all K logical rows are complete on both sides. |
| Scan | Issue contiguous accepted x values from zero; bubbles do not advance x. Hold y and oldest bank fixed. Load only future rows into reusable spare banks. |
| Drain | Stop reads after the last x; retain the complete active window while pending arithmetic and tags advance. |
| Row clear | Let the clocked sink capture the final result, then clear horizontal state on the separate permitted edge. Retire the oldest row only at this boundary. |
| Frame abort / reset | Flush pending results and software ownership without clearing physical RAM. Reload the new frame before restarting. |
| Sink | Accept every valid result; there is no DUT output-ready port. Check full packed record, cost, disparity, coordinates, row-last, duplicate/missing pixels and total frame coverage. |

## Independent checks

The subsequent [[Independent Control Validation|fresh-instance authored cross-check]] is a separate frozen replay bench, not another review of this bench. Its report preserves the original surviving blind mutation and the explicitly versioned v2 repair rather than treating independent authorship as proof of complete coverage.

The protocol monitor reconstructs residency and L/R word completion from accepted load ports, not controller readiness flags. It protects active rows during bubbles as well as read edges. A producer-side logical-row label identifies fixture data and is checked against physical addressing and payload; it is not a DUT readiness signal.

The arithmetic oracle sums all K×K absolute differences for every candidate from immutable flat raw images and chooses the smaller disparity on ties. It never reads DUT memories, tap history, rolling sums or lane internals. Output timing is checked before NBA updates (the real consumer edge) and after updates.

Required scenarios: independent right-tail delay causing a genuine next-row wait; simultaneous prefetch/read; repeated no-copy bank reuse; partial words; multiple spare rows; random input bubbles; full-frame output coverage; all-equal ties, maximum differences and known shifted images; reset/frame-clear aborts and clean restarts. Small/empty interiors must complete without spurious results.

## Implementation and evidence

**Implemented and exercised with Icarus.** [Test-only controller/monitor/sink](../tests/rtl/tb_stereo_control.sv) and [fault checker](../scripts/check_control_sensitivity.py) are registered in the normal runner/sensitivity workflow. No functional RTL changed.

| Executed check | Actual result |
|---|---|
| Default `control` matrix | All ten configurations pass: K=1/3/5/11, P=1/8/10, W=1/3/5/9/13/64/640, T=1/3/5/7/32 and S=1/2/3 across the selected combinations. This is not their Cartesian product. |
| Initial combined production geometry | Before the single-pulse follow-up: K=11/P=8/W=640/T=32/S=1/**H=13**, seed 12345: four completed jobs, two aborted jobs, 5,378 checked captured records, 14 directed right-tail wait cycles, 1,095 read/load overlaps and 14 cancelled in-flight winners. This short frame does not wrap the 12-bank ring; longer matrix cases separately cover repeated wraps. |
| Additional boundary cases | H=2<K=3 completes with zero outputs; P=16/S=5/H=21 with seed 777 passes; K=3/W=9/T=3/S=2/H=6 passes with a generated VCD. |
| Accepted-port protocol sensitivity | All five intentionally unsafe schedules fail at their required monitor diagnostic: premature right-tail promotion, active-bank writes during a read bubble, early clear, wrong oldest bank and duplicate x. These are testbench checks, not synthesized DUT guards. |
| Whole-path RTL sensitivity | Positive real-DUT baseline passes; all four compiled mutants are caught by the output oracle: mispacked disparity field, right RAM loaded with left pixels, a one-cycle winner-tag skew and backend frame-clear incorrectly gated by frontend validity. Syntax errors do not count as detections. |
| Existing canonical sensitivity | All 38 existing RTL mutants and nine existing real-DUT parameter/address/active-bank guards pass their rejection checks; the canonical command then runs the new control checks. |
| All-suite reduced smoke | `--case 3:8 --random-cycles 0` passes 21 cases including all registered suites and the six legacy cases. This is not the complete default matrix. |
| Exact-source documentation | All 13 functional RTL walkthrough/standalone-bench mappings pass after the documentation edits. All 14 RTL files, including the smoke wrapper, retain their recorded fingerprints. |
| Initial artifact readback | Before the single-pulse follow-up, Python independently checked 26,348 captured CSV records across the ten matrix and four targeted cases: complete-frame coordinate sets, counts, duplicates, packing, zero/max ties and known-shift winners all passed. The arithmetic oracle itself remains the SV full raw-window comparison. |
| Native Questa | All referenced RTL and the new bench compile with zero errors/warnings. Fresh batch simulation fails licence checkout (exit 12: the existing one-session node-locked instance is running). No user session was closed; no native simulation pass is claimed. |

The earlier full-default rerun under `build/vault-tidy/` reached a **600-second timeout** in the existing packed K=11/W=640/T=32 reference case. It is not a fresh full-default pass. The successful new short production case and reduced all-suite smoke do not silently replace that missing result.

### Independent review follow-up: single-pulse abort/restart

The first bench immediately cleared again at the next job's start. Independent review identified that second pulse as a material coverage blind spot. A retained before-fix experiment reproduces it: the real baseline **and a compiled backend busy-clear mutant both pass the old bench**. The mutant drops backend frame-clear whenever frontend data is valid; it is not a change to real RTL.

The current bench checks one abort pulse followed by **`LAT+2` quiet clock edges with reset released and both clears low**, then reloads and starts the next frame **without an additional clear**. Its existing oracle checks every quiet edge before and after registered updates. The independent port monitor rejects another reset/frame-clear before the resumed first read; normal row-clear rules prevent an intervening row clear. Counters require two accepted-read restarts and the exact quiet-edge coverage. The frame-clear abort now occurs at `min(FIRST_X+2,W-1)` so, where the width permits, canceled work has reached the backend rather than only the frontend handoff.

**Fresh results:** all ten strengthened control configurations, H<K, 16-bit/five-spare stress and the VCD case pass, plus the 21-case reduced all-suite smoke. The positive sensitivity baseline passes; five illegal caller schedules and all four compiled RTL mutants fail at their intended diagnostics. The formerly escaping mutant now fails the output oracle during the abort quiet interval: a ghost nonzero record is observed where zero is required. Read-only independent follow-up confirms the original gap is closed and reports no correctness regression.

The strengthened **K=11/P=8/W=640/T=32/S=1/H=13** simulation also passes: four completed jobs, two single-pulse restarts, 5,378 checked records, 28 quiet edges and 16 canceled in-flight winners. Its Python-runner attempt reported an anomalous negative timeout despite complete frame CSVs; that failed command is retained in `production.txt`, not relabeled a pass. A separate direct `vvp` rerun of the compiled simulation returns **exit 0 and its actual final PASS marker**, retained in `production-direct.log` and `production-direct.exit`. Across the ten matrix and four targeted runs, the current reports contain **26,344 records, 24 single-pulse restarts and 226 checked quiet edges**. The changed aborted-frame schedule can change captured prefix counts; the earlier 26,348-record checkpoint remains historical.

Before/after evidence is under `build/control-emulation/single-abort/`, including `bench-before.sv`, `before-evidence.json` and the two original simulation logs. Updated ordinary-run reports are in the same folder; the permanent fourth mutant and its intended oracle diagnostic are in `build/control-sensitivity/`. All changes are test-only or documentation; no synthesized controller or hardware protection is added.

### Run and inspect

```sh
python scripts/run_tests.py --suite control
python scripts/run_tests.py --suite control --case 3:8:9:3 --spare-rows 2 --height 6 --vcd
python scripts/run_tests.py --suite control --case 11:8:640:32 --height 13 --seed 12345 --random-cycles 300 --timeout 1200
python scripts/check_control_sensitivity.py
```

In an available Questa session, use `set part control` then `do scripts/questa_lab.do` from the repository root. The macro changes that session's active simulation; the automated checks did not disturb the user's existing simulation.

Retained local reports are under `build/control-emulation/`: `matrix.txt`, `production.txt`, `short-height.txt`, `wide-pixels-spares.txt`, `waveform.txt`, `all-suite-smoke.txt`, `sensitivity.log`, `walkthrough.log`, `artifact-evidence.json`, `rtl-baseline.json` and `questa/{compile,simulation}.log`. Each `build/control/<case>/` holds `control_results.csv` and `control_frames.csv`; the waveform example also has `waveform.vcd`. Individual fault diagnostics and source fingerprints are in `build/control-sensitivity/evidence.json` and its case subdirectories. These generated files are ignored locally; CI is configured to upload control CSVs and fault evidence when it runs. No new CI run is claimed.

### Read the bench in four pieces

1. **Fixtures and oracle:** immutable left/right pixel arrays, full K×K summation per candidate, and a wall-clock expected-result queue.
2. **Independent monitor:** separately reconstruct accepted L/R word completion and physical-bank residency; enforce sequential coordinates, active-row lifetime and a safe clear edge.
3. **Caller emulation:** `WAIT_ROW → SCAN → DRAIN → ROW_CLEAR`, independently stalled load selection, readiness gating and no-copy ring reuse. There is no DUT-ready signal to consult.
4. **Clocked sink and scenarios:** consume old registered outputs before NBA, check post-update outputs separately, build a duplicate-free frame record, then exercise abort/reload/restart and the directed image patterns.

## Limits

This verifies a legal controller strategy in simulation, not a synthesized controller, Avalon/SDRAM transactions, downstream backpressure, fitted timing, board behavior or end-to-end accelerator throughput.
