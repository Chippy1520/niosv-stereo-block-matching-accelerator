# Verification
#verified

[[Home]] → **Verification** · [[Integration Readiness]] · [[Verification Map]] · [[Testbench Guide]]

## Current hierarchy of checks

Thirteen functional RTL blocks have registered standalone benches: [[Row Word Bank]] → [[Packed Circular Row Buffer]] → [[Stereo Frontend - Code Walkthrough]], and [[SAD Search Backend]] → [[Stereo SAD Datapath]]. Storage now has K active plus parameterized spare rows; accepted-read gating preserves spare-write headroom. [[Column Pairing Verification]] remains a local integration bench and the Python/deque checks remain. No FIFO, ownership/readiness controller, transport or board integration is claimed. See [[Testbench Guide]] and [[Hands-on Testbench Lab]].

```sh
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py
```

The [current spare-row ledger](../docs/verification/spare-row-prefetch.md) records the expanded default regression, S=1/2/3 and extra S=5/6 tests. All **38 targeted production mutants** and **nine invalid-parameter/address/active-bank cases** are rejected. Full-width frontend/packed-compute cases use 41 rows with S=1, not 480; backend-only cases still use 38 rows. Earlier [110-case frontend](../docs/verification/packed-frontend.md) and [130-case compute](../docs/verification/compute-datapath.md) reports remain historical. Teaching checks are separate.

**Historical native teaching checkpoint:** Questa Intel Starter FPGA Edition 2021.2 ran the beginner baseline and all eight macro-selected component/pairing directed cases using `scripts/questa_lab.do`. Local logs are `build/lab/questa*.log`. This is functional simulation, not physical timing; CI uses Icarus and also exercises the teaching baseline/fault checks.

The **pre-repair** audit ran 66 native Questa simulations including teaching benches. The spare-row store/frontend/complete-path native compile checkpoint passed with zero errors/warnings **before the final audit-only store-bench extension**; that extension has Icarus evidence, not a new native compile/run. Fresh native runtimes remain blocked by the existing user's one-session node-locked license, which was not disturbed. Current functional passes are Icarus, not relabeled old native evidence.

Local simulator: Icarus Verilog 13.0. GitHub Actions runs the same benches on Ubuntu using its packaged Icarus version. CI logs identify its installed version; the checks do not depend on matching the local version.

## Recorded evidence

- [[Independent Control Validation]] — three passing real-DUT configurations; original blind v1 evidence retained, and separately frozen v2 closes its stimulus-masking gap. All five original faults plus a symmetric follow-up are rejected without changing the oracle or SV checker. Separate from the canonical suite and CI.
- [[Control Emulation]] — simulation-only row/frame scheduler around the real complete compute top, independent accepted-port readiness/ownership monitor, raw-image winner oracle and clocked framebuffer sink. Includes bad-caller schedules and compiled RTL wiring faults; not an implemented hardware controller.
- [[Integration Readiness]] — current packed-frontend/search readiness and remaining controller/platform gates. The compute path exists; the board system does not.
- [[docs/verification/spare-row-prefetch|Current spare-row ledger]] — parameter/configuration-specific simulation, mutants, guards, actual RAM mapping and council reconciliation. Detailed counts belong here rather than being copied into every hub.
- [[Integration Audit - Serial Baseline|Archived serial-baseline audit]] — original pre-repair execution table, native Questa results and subsequent serial-storage repair. Its old missing-frontend/search statements are historical.
- [[docs/verification/packed-frontend|Historical K-only frontend checkpoint]] · [[docs/verification/compute-datapath|Historical K-only compute checkpoint]].

- Scratch runner output: [sim/results.txt](../sim/results.txt). By default each runner invocation overwrites this file; `--report build/<name>.txt` isolates named runs. A focused run is not a retained whole-suite report. Use the ledger's named retained logs for verification claims.
- Original buffer milestone: [column-buffer-simulation.txt](../docs/verification/column-buffer-simulation.txt).
- Engine/module milestone: [single-engine-simulation.txt](../docs/verification/single-engine-simulation.txt).
- Extra-seed engine/waveform run: [single-engine-extra-seed.txt](../docs/verification/single-engine-extra-seed.txt).
- Synthesis summary: [single-engine-synthesis.md](../docs/verification/single-engine-synthesis.md).
- Comparator-only synthesis: [comparator-synthesis.md](../docs/verification/comparator-synthesis.md).
- Right-shift synthesis: [right-shift-synthesis.md](../docs/verification/right-shift-synthesis.md); full default K=11/P=8/TAPS=32, not a reduced smoke top.
- Left-delay synthesis: [left-delay-synthesis.md](../docs/verification/left-delay-synthesis.md); full default K=11/P=8, zero errors/warnings and 90 logic cells before fitting.
- GitHub Actions uploads fresh results and test artifacts for each run.

## Synthesis versus timing

**Current integrated evidence:** the [spare-row ledger](../docs/verification/spare-row-prefetch.md) records real production-width packed-store, frontend and complete 32-lane-top A&S builds, including K+SPARE_ROWS RAM-node counts. These are pre-fit resource measurements, not achieved frequency, scheduling bandwidth or board throughput.

**Earlier component records:** Quartus Prime Lite 22.1 Analysis & Synthesis of `Stereo_SAD_Engine.qpf` passed with **zero errors and zero warnings**. Default K=11, PIXEL_W=8; post-synthesis report says **770 logic cells**, before fitting. This is not a final resource count or Fmax measurement.

The original `Stereo_SAD.qpf` buffer-only project also previously passed (one processor-count warning). Its local settings have been preserved. The history array uses asynchronous reads and maps to logic rather than inferred block RAM. The multidimensional tree produces an informational netlist-writer bus-regrouping message, not a synthesis error.

No fitting, fully constrained timing, board programming, CPU integration or physical image test has been claimed.

`Stereo_SAD_RightShift.qpf` passed Analysis & Synthesis with zero errors, zero warnings and 2883 logic cells before fitting. Its wide tap output is an internal-bus abstraction, not a board pinout. `Stereo_SAD_LeftDelay.qpf` passed with zero errors/warnings and 90 logic cells. These are component checkpoints; current integration evidence is linked above.

The separate default 32-lane comparator component passed Quartus Analysis & Synthesis: zero errors, one processor-count warning, 1622 logic cells before fitting. It does not demonstrate multi-engine timing or integrated winner-take-all image output.

`Stereo_SAD_RowBuffer.qpf` now targets the **real K=11/P=8/IMG_W=640 row buffer** with its bank dependency: 697 logic elements, 33 registers and 56,320 logical memory bits; 11 M9K RAM nodes appear in the RAM Summary. The project and isolated inference guard both pass Analysis & Synthesis. The earlier width-16 logic-only smoke and full-width failures are historical. See [row-buffer-synthesis.md](../docs/verification/row-buffer-synthesis.md).

**Review checkpoint:** user-requested spare-row increment in the implemented compute path, with no new controller or functional-module boundary. Interactive module simplification review resumes after verification. No commit or push in this increment; accelerator controller last.
