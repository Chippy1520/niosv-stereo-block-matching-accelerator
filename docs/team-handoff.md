# Team handoff — stereo SAD FPGA project

This is a shareable snapshot of work in progress, **not a completed board system**. Start with the [README](../README.md), then use the routes below. This document distinguishes implemented hardware, simulation-only scheduling and future control/system work.

See the [publication-time verification record](verification/github-snapshot.md) for fresh check outcomes, synthesis resources and explicit limits.

## What teammates can inspect now

| Area | Current state |
|---|---|
| Packed input storage | Independent left/right four-pixel word loads into circular stores with `K + SPARE_ROWS` physical rows; at least one spare. Both sides share explicit bank/word addresses. |
| Column frontend | Shared explicit column reads, matching left delay, right disparity-column cache, per-tap warmup validity and aligned coordinate/row-last tags. |
| SAD computation | One existing `sad_engine` per fixed disparity, each containing `column_sad` and `column_sum_buffer`; common-interior qualification and lower-disparity tie breaking. |
| Complete compute top | `rtl/stereo_sad_datapath.sv` connects packed storage through minimum selection to tagged winners and a zero-on-invalid 32-bit record. |
| Verification | Standalone self-checking benches, independent raw-pixel window scoreboards, caller-emulated frame/row integration, fault-sensitivity checks and a separately authored bounded replay suite. |
| Synthesis | Quartus Analysis & Synthesis resource/RAM-mapping evidence exists. This is not fitting, TimeQuest timing closure or measured board performance. |
| Learning/design material | Exact-source, line-explained module walkthroughs and linked Obsidian notes/canvases. Historical paper plans are labelled as plans, not current RTL maps. |

The serial `circular_row_buffer` and its RAM primitive remain a **separate reference path**, not extra storage in the packed compute path. Current defaults target an 11×11 window, 8-bit grayscale, width 640 and 32 fixed disparities; parameters are compile-time, not runtime configuration.

## Read in this order

1. [Integration readiness](../Verification/Integration%20Readiness.md): implemented capabilities versus open integration gates.
2. [Project plan](../System/Project%20Plan.md): active decisions, control direction and future acceptance criteria.
3. [Datapath study guide](../Accelerator/Datapath%20Study%20Guide.md): module roles, interfaces and timing.
4. [Complete compute-top walkthrough](../Accelerator/Stereo%20SAD%20Datapath.md) and [compute specification](accelerator-datapath-spec.md).
5. [Control-emulated integration](../Verification/Control%20Emulation.md) and [independent validation](../Verification/Independent%20Control%20Validation.md): what the tests actually establish and what they do not.
6. [Progress history](progress.md): preserve the distinction between older checkpoints and the current snapshot.

GitHub renders ordinary Markdown and Mermaid. For the full linked-note navigation and editable `.canvas` views, clone/download the repository and open its root as an Obsidian vault. Personal Obsidian settings, workspace state and local simulator transcripts are not required or included in this publication.

## Reproduce the checks

Use Python **3.12** (the CI version) and install Icarus Verilog (`iverilog` and `vvp` on PATH). No third-party Python packages are required for these checks. The independent replay's modern type annotations require Python 3.10 or newer.

```sh
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py
python scripts/run_testbench_lab.py --check-faults --examples
```

The full regression includes production-width raw-window references and can take substantially longer than a small-module test. A quick smoke test is **not** a replacement for that full run:

```sh
python scripts/run_tests.py --case 3:8 --random-cycles 0 --report build/team-smoke.txt
```

The separately authored replay suite is intentionally outside the canonical regression/CI matrix. On Windows its default tool paths refer to a local, untracked portable Icarus installation; Linux/macOS users should explicitly select their installed executables:

```sh
python tests/independent_control/run_independent.py --self-check --iverilog "$(command -v iverilog)" --vvp "$(command -v vvp)" --out-dir build/team-independent
```

The executable overrides must be full paths: this frozen runner resolves path arguments directly rather than searching PATH. On Windows, supply the installed `.exe` paths instead. See its [frozen author README](../tests/independent_control/README.md) for the authoring protocol and bounded matrix; that README's author-side status is historical. The [parent validation note](../Verification/Independent%20Control%20Validation.md) records completed DUT and mutation experiments. V2 deliberately repairs a revealed coverage gap and must not be described as a newly blind experiment. Historical raw logs, original frozen v1 copies and disposable mutants live under local ignored `build/` and are not part of a clone.

Optional actual Quartus compute synthesis, with Quartus Lite 22.1 installed:

```sh
python scripts/check_row_buffer_synthesis.py --quartus-map /path/to/quartus_map --top datapath --taps 32
```

Use the installed `quartus_map.exe` path on Windows. The helper creates an isolated project under `build/`; it does not fit the board or edit component project files. Existing `.qpf` projects are component-level projects, not a complete board top. See the README's Quartus section.

GitHub Actions runs the canonical checks and teaching tests, not Quartus or board hardware. Its workflow run is the public source for cloud pass/fail and downloadable simulation artifacts.

## Control direction agreed so far — not implemented

- A **central FSM** coordinates distributed block controllers and global frame/row/bank ownership.
- **One local controller per complete PE** covers both its column calculator and history buffer. The same controller design is reused per PE instance.
- Other block sequencing and a shared L/R scanner remain planning work; command/status interfaces and precise local state transitions are not frozen.
- Consider `.smf` for graphical state-machine design and `.bdf` for structural views in Quartus. Neither exists yet; source-of-truth, generated HDL, synchronous-reset and output-registration policies need agreement before adoption. Existing `rtl/*.sv` remains authoritative.
- The existing datapath has valid-only streaming interfaces. Do not independently stall stages, discard warmup columns, clear horizontal state before final-result consumption, or overwrite any active row bank during a bubble.

## What is still missing

1. Interactive datapath simplification review and a frozen controller contract.
2. Synthesizable autonomous loading/readiness/scan/drain/clear/abort control, with independent standalone and integration tests.
3. Transport/output-capacity policy, Avalon/SDRAM/CSR integration and CPU cache ownership.
4. Verified Nios V/toolchain/external-SDRAM system integration in this repository.
5. Board wrapper, pin/I/O constraints, fitting and timing closure.
6. Repeated board frame comparisons and measured throughput/speedup under equivalent search and memory conditions.

A previous separately recorded Nios V Hello World does not prove those system gates. No board bitstream, fitted frequency, sustained 32-lane throughput or completed visual controller design is claimed.
