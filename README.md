# Nios V Stereo Block-Matching Accelerator

[![RTL verification](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator/actions/workflows/rtl-tests.yml/badge.svg)](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator/actions/workflows/rtl-tests.yml)

SystemVerilog stereo SAD accelerator under incremental development for the **Terasic DE2-115 (Cyclone IV E, EP4CE115F29C7)**, with **Nios V** as the system-integration target. This repository doubles as an **Obsidian study/design vault**.

## Team handoff — current project state

**Working compute path:** packed left/right row loading → circular stores with spare-row prefetch → aligned disparity columns → parallel SAD engines → minimum comparator → tagged 32-bit result. The serial row-buffer path is retained separately for reference.

**Next control direction, not implemented:** a central FSM coordinates distributed block controllers, with **one controller per complete PE** covering its column calculator and history buffer. Quartus `.smf` state diagrams and `.bdf` structural views are being considered; no such design files have been created, and their source-of-truth workflow is not frozen.

**Not a board-ready accelerator:** autonomous control, memory transport, Nios V/SDRAM integration, fitting/timing closure and measured end-to-end throughput remain open. Publishing this snapshot does not close those gates or the interactive datapath review.

- **[Teammate handoff: reading route, reproduction commands and next decisions](docs/team-handoff.md)**
- [Publication-time verification: fresh checks and explicit limits](docs/verification/github-snapshot.md)
- [Current implementation/readiness](Verification/Integration%20Readiness.md) · [Active plan](System/Project%20Plan.md) · [Progress history](docs/progress.md)

## What works now

- **Circular row buffer:** one image stream, K clocked row RAM banks, and one vertical column out. Its internal `row_ram_bank` is independently tested; the full-width default now maps to M9K. No disparity shift inside.
- **Packed-load stereo frontend:** independent four-pixel/32-bit row loads, explicit shared column reads, two stores with **K active rows plus `SPARE_ROWS` prefetch rows (default/minimum one)**, existing left delay/right cache and matching `(x,y,row_last)` tags. Prefetch writes may share the active read's word address because spare banks do not read. No-copy bank rotation/readiness remains caller-controlled; no FIFO or controller is implemented. The serial buffer above remains a separate lesson/reference, not extra storage in this path.
- **Pipelined column-SAD calculator:** parallel unsigned absolute differences and a registered balanced reduction tree.
- **Circular column-history buffer:** retains K−1 column sums and a running total; includes the final window-SAD adder.
- **Single SAD engine:** connects those modules, accepting already-aligned vertical pixel columns and returning full K×K window costs.
- **Pipelined comparator tree:** reduces aligned valid `(SAD, disparity)` candidates; lower SAD wins, then lower disparity. Reused inside the full-search backend.
- **Right-column shift cache and left delay:** whole-column disparity taps with prefix warmup and matching left alignment, connected through the packed frontend to the search.
- **Full-search backend:** `sad_search_backend` owns parallel existing engines, common-interior/all-lane qualification, the existing comparator and wall-clock winner tags. Prefix warmup is allowed; mid-row lane holes are not.
- **Complete compute datapath:** `stereo_sad_datapath` connects real packed storage/alignment through the search to tagged winners and a zero-on-invalid 32-bit record, with no extra pipeline register, FIFO or controller.
- **Controller-emulated integration tests:** a simulation-only frame/row scheduler drives that real top with independently delayed L/R words, complete-row readiness, no-copy spare-bank reuse, input pauses, drain/clear and single-pulse abort/restart. A separate port monitor and raw-image framebuffer scoreboard check the contract, including a clear-deasserted quiet interval and restart without another clear. The strengthened ten-case control matrix passes; five bad caller schedules and four additional RTL mutants are rejected. See [scope and evidence](Verification/Control%20Emulation.md); this does not implement a hardware controller.
- Defaults: **11×11**, **8-bit** pixels, **640** columns, **32 fixed disparities**. Controllers, transport and external-memory output placement are not part of this compute top.
- **Fresh-instance independent cross-check:** three bounded whole-datapath configurations pass (865 mature winners). The frozen blind v1 exposed a write-enable coverage gap; separately frozen, user-authorized v2 poisons inactive data symmetrically and rejects all five original compiled faults plus a symmetric follow-up. Oracle, scheduling, SV checker and baseline outputs remain unchanged. Original evidence is preserved; v2 is not a newly blind experiment or a full-suite claim. See [independence, results and limits](Verification/Independent%20Control%20Validation.md).
- Thirteen functional RTL blocks have exact-source, code-adjacent walkthroughs and registered standalone benches. **All 152 default regression cases passed for this publication**, including the final audit-only store-bench extension and ten-case control-emulated matrix; see the [publication-time verification](docs/verification/github-snapshot.md). Historical **142-case** spare-row and subsequent **14-case ad-hoc** audit checkpoints are preserved in the [spare-row ledger](docs/verification/spare-row-prefetch.md), including extra S=5/6 stress, consecutive bank rotations and W=5/9 frontend cases. Default-width packed-path cases use 41 rows, not 480; direct-column backend remains 38. Earlier 130-case/full-height evidence is [preserved separately](docs/verification/compute-datapath.md).
- All **38 targeted arithmetic/timing/flush/wiring/tie/valid/RAM/packing/spare-propagation mutants** and **nine invalid-parameter/address/active-bank contract cases** are rejected. Teaching tests remain separate.
- Actual spare-row integrated **32-lane compute-top A&S** passes: **30,274 LE, 15,519 registers, 122,880 logical memory bits, 24 M9K RAM nodes**, zero errors/two warnings. Earlier one-/three-lane builds predate spare rows. This is synthesis area, not fitting, achieved throughput or an equivalent-search speedup study.
- Production-width spare-row packed-store A&S: **632 LE, 8 registers, 61,440 memory bits, 12 M9K nodes**. Both-store/32-tap frontend: **4,264 LE, 2,985 registers, 122,880 memory bits, 24 M9K nodes**. Each has zero errors/one processor-count warning. See [current evidence](docs/verification/spare-row-prefetch.md); [K-only evidence](docs/verification/packed-frontend.md) is historical.
- Engine Analysis & Synthesis passed in Quartus Prime Lite 22.1 with **zero errors and zero warnings**, reporting 770 logic elements before fitting. The **real row-buffer default** (`K=11`, 8-bit pixels, `IMG_W=640`) now passes with **697 logic elements, 33 registers and 56,320 logical memory bits**, with 11 M9K RAM nodes in the RAM Summary. The earlier width-16 logic-only smoke and full-width failures are historical baselines. No fitted timing result is claimed; see [row-storage evidence](docs/verification/row-buffer-synthesis.md).
- Default 32-lane comparator component Analysis & Synthesis passed in Quartus Lite 22.1 with **zero errors, zero warnings and 1622 logic elements before fitting** in the fresh single-processor audit. The older run's processor-count warning is recorded in its historical report. This is not a fitted timing or integrated bank result.
- Default right-shift component (K=11, 8-bit pixels, 32 taps) Analysis & Synthesis passed with **zero errors, zero warnings and 2883 logic cells before fitting**. Its wide tap bus is internal wiring, not a board pinout.
- Matching left delay Analysis & Synthesis passed with **zero errors, zero warnings and 90 logic cells before fitting**.
- A hands-on bench-writing guide and Questa/ModelSim macro are included; the beginner lab and eight selected component/pairing directed simulations were actually run in Questa Intel Starter Edition 2021.2.
- The historical pre-repair audit passed **66 native Questa simulations**; later K-only checkpoints passed 110 and 130 Icarus cases. Spare-row native compilation passed with zero warnings before the final audit-only store-bench extension; that extension has Icarus evidence, not a new native run. Fresh native simulation attempts remain blocked by the user's existing node-locked session, which was not closed. See [spare-row evidence](docs/verification/spare-row-prefetch.md) and the [archived serial-stage audit](Verification/Archive/Integration%20Audit%20-%20Serial%20Baseline.md).

- A consolidated datapath study guide links every exact-code walkthrough and covers packing/widths, stored state, warmup, clock timing, independent scoreboards and integration limits. `python scripts/run_testbench_lab.py --examples` additionally runs a seven-module teaching bench with 40 checked stimulus edges; it is not an integrated accelerator or 40 extra regression configurations.
- Linked architecture notes, an Obsidian canvas, and a complete line-by-line RTL walkthrough.

**Review checkpoint:** the spare-row change and its returned reviews are reconciled; interactive module-by-module simplification review remains open. The user has now authorized publication of the current project snapshot; earlier no-publish entries below are historical. Readiness/ownership and row-boundary scheduling remain caller obligations; hardware control is still a separate future milestone. See the [decision/evidence ledger](docs/verification/spare-row-prefetch.md).

**Not implemented here yet:** autonomous control, replay/group scheduling and cross-group best merge, runtime kernel configuration, Nios V/Avalon integration or a board-ready bitstream. Prior notes record a separately demonstrated Nios V Hello World; its working board project is not included here.

## Start here

- **[Integration readiness — current compute status, evidence and remaining system gates](Verification/Integration%20Readiness.md)**
- **[Datapath study guide — every implemented module, how it works and what to test](Accelerator/Datapath%20Study%20Guide.md)**
- [Project dashboard](Home.md)
- **[Main project plan — future modules and integration gates](System/Project%20Plan.md)**
- [Complete code and line-by-line explanation](Accelerator/Engine/Column%20Sum%20Buffer%20-%20Code%20Walkthrough.md)
- [Pipelined column calculator: code and explanation](Accelerator/Engine/Pipelined%20Column%20SAD%20Calculator.md)
- [Single engine: code, interfaces and row timing](Accelerator/Engine/Single%20SAD%20Engine.md)
- [Circular row buffer: code and abstraction](Accelerator/Frontend/Circular%20Row%20Buffer.md)
- [Packed-load frontend: exact RTL, timing and raw-image bench](Accelerator/Frontend/Stereo%20Frontend%20-%20Code%20Walkthrough.md)
- [Full-search backend: exact RTL and line explanations](Accelerator/SAD%20Search%20Backend.md) · [Complete compute datapath](Accelerator/Stereo%20SAD%20Datapath.md) · [frozen specification](docs/accelerator-datapath-spec.md)
- [Packed row-store datapath](Accelerator/Frontend/Packed%20Circular%20Row%20Buffer.md) · [word RAM primitive](Accelerator/Frontend/Row%20Word%20Bank.md) · [frozen interface contract](docs/packed-frontend-contract.md)
- [Comparator tree: exact RTL and code walkthrough](Accelerator/Minimum%20Comparator%20Tree%20-%20Code%20Walkthrough.md)
- [Right-column shift register: code, tap validity and timing](Accelerator/Frontend/Right%20Column%20Shift%20Register.md)
- [Left-column delay: exact code and timing](Accelerator/Frontend/Left%20Column%20Delay.md)
- **[Hands-on testbench-writing lab — practise individual modules](Verification/Hands-on%20Testbench%20Lab.md)**
- [Local left/right pairing verification](Verification/Column%20Pairing%20Verification.md)
- [System map: current datapath and consolidated future plan](System/Module%20Blocks.canvas)
- [Implemented accelerator components and compute-search boundary](Accelerator/Accelerator%20Blocks.canvas)
- [One engine's submodules](Accelerator/Engine/SAD%20Engine%20Blocks.canvas)
- [Testbench guide](Verification/Testbench%20Guide.md)
- [Synthesizable SystemVerilog modules](rtl/)
- [Buffer interface contract](Accelerator/Engine/Column%20Sum%20Buffer.md#interface-contract)
- [Rolling SAD mathematics](Accelerator/Engine/Rolling%20SAD%20Math.md)
- [Verification](Verification/Verification.md)
- [Progress log](docs/progress.md)
- [GitHub update workflow](docs/github-workflow.md)

### Open in Quartus

Open **`Stereo_SAD_RightShift.qpf`** for `right_column_shift`, **`Stereo_SAD_RowBuffer.qpf`** for `circular_row_buffer`, **`Stereo_SAD_Engine.qpf`** for `sad_engine`, or **`Stereo_SAD.qpf`** for the original buffer-only component. Keep companion `.qsf`, `constraints/`, and `rtl/` paths intact. Clock constraint: provisional 50 MHz.

This is an **Analysis & Synthesis component project**, not a board top-level. Physical pin assignments, external I/O timing, fitting, processor integration and programming are later gates.

### Run tests

Requirements: Python 3 and Icarus Verilog (`iverilog` and `vvp` on PATH).

```sh
# Ubuntu/Debian: sudo apt-get install iverilog
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py

# Individual stages or waveform output:
python scripts/run_testbench_lab.py --check-faults
python scripts/run_tests.py --suite delay --case 3:8 --vcd
python scripts/run_tests.py --suite pairing --case 3:8:3 --vcd
python scripts/run_tests.py --suite column
python scripts/run_tests.py --suite buffer
python scripts/run_tests.py --suite row --case 11:8:8 --vcd
python scripts/run_tests.py --suite word-bank --case 160:32
python scripts/run_tests.py --suite packed-row --case 3:8:7 --vcd
python scripts/run_tests.py --suite packed-row --case 3:8:7 --spare-rows 2
python scripts/run_tests.py --suite frontend --case 3:8:9:5 --vcd
python scripts/run_tests.py --suite search --case 3:8:13:5 --vcd
python scripts/run_tests.py --suite datapath --case 3:8:13:5 --vcd
python scripts/run_tests.py --suite datapath --case 3:8:13:5 --spare-rows 3
python scripts/run_tests.py --suite control
python scripts/run_tests.py --suite control --case 3:8:9:3 --spare-rows 2 --vcd
python scripts/check_control_sensitivity.py
python scripts/run_tests.py --suite engine --case 11:8 --vcd
python scripts/run_tests.py --suite comparator --case 32:15 --vcd
python scripts/run_tests.py --suite shift --case 11:8:32 --vcd
```

Windows may alternatively use the local, untracked portable installation at `tools/mingw64/bin/`. No third-party Python packages are required by these tests. Standalone SV benches are tracked in `tests/rtl/`. Compiled simulations, optional waveforms and legacy vectors are generated in `build/`; results go to `sim/results.txt`. See the testbench guide for parameter matrices and extra seeds.

GitHub Actions reruns the canonical walkthrough, regression, fault-sensitivity and teaching checks for every push and pull request. Simulation output is available as a workflow artifact. The standalone independent replay is separately run; cloud CI does not run it, Quartus or board hardware tests. Every new functional RTL module must arrive with its code-adjacent walkthrough and standalone self-checking bench, registered in the runner; `check_walkthrough.py` rejects missing coverage.

### Open in Obsidian

Choose **Open folder as vault** and select the repository root. Start at **Home**, then follow **System Architecture** → **Accelerator Architecture** → **Stereo Frontend** / **SAD Engine Architecture** → module notes and **Verification Map**. Folders alone do not create Graph edges. **System/Project Plan.md** owns current review and future work; implemented modules retain their exact-source walkthroughs. The old serial-stage audit is preserved in **Verification/Archive/** and linked from current readiness. Recent personal bookmarks, search/Graph settings, appearance changes and the local navigation CSS are not part of this snapshot; no community plugins or personal workspace files are required to read it. The project canvases remain included.

## Architecture direction

```text
host frames (optional Ethernet) ──┐
Nios V control / CPU reference ────┼→ Platform Designer interconnect ↔ SDRAM controller ↔ shared SDRAM
VGA display (optional) ────────────┘               ↕
                                         stereo SAD accelerator (planned integration)
                                            SDRAM transport + CSRs/controller
                                            → two row buffers → right-column cache/taps
                                            → P_LANES parallel sad_engine instances
                                                column_sad → column_sum_buffer
                                            → comparator tree → cross-group best merge
                                            → shared-SDRAM output writeback
```

[System map](System/Module%20Blocks.canvas) and [accelerator map](Accelerator/Accelerator%20Blocks.canvas) distinguish the current compute components from future system integration; the [SAD engine map](Accelerator/Engine/SAD%20Engine%20Blocks.canvas) details the implemented single-lane wrapper. The original [whole-system paper plan](System/Paper%20System%20Plan.canvas) and [accelerator paper plan](Accelerator/Paper%20Design%20Plan.canvas) preserve intended system/accelerator layouts. Ethernet packet staging and VGA display remain optional and unimplemented. `P_LANES` is a compile-time choice: fewer lanes over a larger search range require unimplemented replay/group scheduling and best-state merging.
The history buffer updates `H_next = H - oldest + newest`; it must retain outgoing values, not just H. The registered SAD is `H + newest` using the pre-update H. Kernel size is currently a synthesis-time parameter. Clear discards a simultaneous valid input and flushes all pending engine work. For normal row boundaries, drain ceil(log2(K))+1 invalid-input clock edges before asserting clear on a separate edge. Coordinates, borders and lane validity require integration-level control.

The shared-SDRAM system proposal remains an integration goal; its implementation is not implied by the working buffer.

## Preserved system planning and reports

Existing feasibility work and Git history are retained, not replaced by the component milestone:

- [Feasibility report (PDF)](docs/stereo_block_matching_feasibility_report.pdf) · [source](docs/stereo_block_matching_feasibility_report.md)
- [Design hierarchy (PDF)](docs/design_hierarchy.pdf) · [source](docs/design_hierarchy.md)
- [Integration checklist](docs/integration_checklist.md)
- [Reference resources](docs/resources.md)
- [Architecture diagrams and editable sources](docs/diagrams/)

These documents describe the broader planned system. The implemented RTL and current verification notes take precedence for claims about this checkout's working capabilities.

## Layout

```text
Home.md / Architecture.canvas   dashboard and broad note map
System/                         system hub, current plan and whole-system canvases
Accelerator/                    accelerator schematic, bank, reducer and timing
Accelerator/Frontend/           stereo frontend canvas and row-buffer walkthrough
Accelerator/Engine/             engine canvas, RTL walkthroughs and SAD mathematics
Verification/                   evidence, testbench guide and graph hub
Verification/Archive/           preserved historical audit, not current status
rtl/ and tests/rtl/             implemented SystemVerilog and standalone benches
scripts/                        HDL test runner and coverage/walkthrough checks
constraints/                    component timing constraints
Stereo_SAD*.qpf/qsf             Quartus buffer, engine and row-buffer projects
.github/workflows/              automatic RTL checks
hardware/ and software/         preserved integration placeholders
docs/                           feasibility reports, diagrams and progress
tools/                          tracked report-generation scripts (portable binaries ignored)
```

## Progress and publishing

This repository is **public**. Only project material belongs here; no credentials, private correspondence, datasets, tool binaries or generated Quartus databases.

During assisted development, completed milestones are tested, documented, committed and pushed. GitHub then runs CI automatically. This is **not an unattended local file watcher**: manual edits remain local until explicitly committed and pushed. See [the workflow](docs/github-workflow.md).
