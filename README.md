# Nios V Stereo Block-Matching Accelerator

[![RTL verification](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator/actions/workflows/rtl-tests.yml/badge.svg)](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator/actions/workflows/rtl-tests.yml)

SystemVerilog stereo SAD accelerator under incremental development for the **Terasic DE2-115 (Cyclone IV E, EP4CE115F29C7)**, with **Nios V** as the system-integration target. This repository doubles as an **Obsidian study/design vault**.

## What works now

- **Circular row buffer:** one image stream, a ring of K rows, and one vertical column out. No disparity shift inside.
- **Pipelined column-SAD calculator:** parallel unsigned absolute differences and a registered balanced reduction tree.
- **Circular column-history buffer:** retains K−1 column sums and a running total; includes the final window-SAD adder.
- **Single SAD engine:** connects those modules, accepting already-aligned vertical pixel columns and returning full K×K window costs.
- **Pipelined comparator tree:** reduces aligned valid `(SAD, disparity)` candidates; lower SAD wins, then lower disparity. Default 32-lane component has five registered levels. The bank that supplies candidates is not yet built.
- **Right-column shift cache and left delay:** registered whole-column disparity taps with per-tap warmup validity and matching left-column/valid alignment. Standalone benches and a local column-pairing bench verify pauses, clear and consumer-edge timing; row-buffer/engine assembly is still planned.
- Defaults: **11×11** window, **8-bit** pixels, **640**-wide row store. The row buffer is not yet connected to the engine, and this is not a full disparity search.
- Seven component self-checking SystemVerilog benches plus a column-pairing integration bench, each with eight parameter cases. Plus six independent Python/deque buffer cases: **70 passing simulation cases**.
- Twelve deliberate arithmetic/timing/flush/wiring/tie/valid faults were rejected by the production benches. The separate beginner lab passed its seven directed beats and caught two compiled faults.
- Engine Analysis & Synthesis passed in Quartus Prime Lite 22.1 with **zero errors and zero warnings**, reporting 770 logic elements before fitting. The row-buffer smoke top (`IMG_W=16`) also passed with zero errors and zero warnings, reporting 3156 logic cells; the `IMG_W=640` default did not finish synthesis within 300 seconds. No fitted timing result is claimed.
- Default 32-lane comparator component Analysis & Synthesis passed in Quartus Lite 22.1 with **zero errors, one processor-count warning, and 1622 logic cells before fitting**. This is not a fitted timing or integrated bank result.
- Default right-shift component (K=11, 8-bit pixels, 32 taps) Analysis & Synthesis passed with **zero errors, zero warnings and 2883 logic cells before fitting**. Its wide tap bus is internal wiring, not a board pinout.
- Matching left delay Analysis & Synthesis passed with **zero errors, zero warnings and 90 logic cells before fitting**.
- A hands-on bench-writing guide and Questa/ModelSim macro are included; the beginner lab and eight selected component/pairing directed simulations were actually run in Questa Intel Starter Edition 2021.2.
- A consolidated datapath study guide links every exact-code walkthrough and covers packing/widths, stored state, warmup, clock timing, independent scoreboards and integration limits. `python scripts/run_testbench_lab.py --examples` additionally runs a seven-module teaching bench with 40 checked stimulus edges; it is not an integrated accelerator or 40 extra regression configurations.
- Linked architecture notes, an Obsidian canvas, and a complete line-by-line RTL walkthrough.

**Not implemented here yet:** disparity alignment between the two row buffers and the engine, the 32-lane wrapper and its comparator wiring, cross-group best merge, runtime kernel configuration, Nios V/Avalon integration, or a board-ready bitstream. Prior notes record a separately demonstrated Nios V Hello World; its working board project is not included here.

## Start here

- **[Datapath study guide — every implemented module, how it works and what to test](Accelerator/Datapath%20Study%20Guide.md)**
- [Project dashboard](Home.md)
- [Complete code and line-by-line explanation](Accelerator/Engine/Column%20Sum%20Buffer%20-%20Code%20Walkthrough.md)
- [Pipelined column calculator: code and explanation](Accelerator/Engine/Pipelined%20Column%20SAD%20Calculator.md)
- [Single engine: code, interfaces and row timing](Accelerator/Engine/Single%20SAD%20Engine.md)
- [Circular row buffer: code and abstraction](Accelerator/Frontend/Circular%20Row%20Buffer.md)
- [Comparator tree: exact RTL and code walkthrough](Accelerator/Minimum%20Comparator%20Tree%20-%20Code%20Walkthrough.md)
- [Right-column shift register: code, tap validity and timing](Accelerator/Frontend/Right%20Column%20Shift%20Register.md)
- [Left-column delay: exact code and timing](Accelerator/Frontend/Left%20Column%20Delay.md)
- **[Hands-on testbench-writing lab — start here before the wrapper](Verification/Hands-on%20Testbench%20Lab.md)**
- [Local left/right pairing verification](Verification/Column%20Pairing%20Verification.md)
- [System-level module blocks: Nios V, Ethernet, SDRAM, VGA, accelerator](System/Module%20Blocks.canvas)
- [Accelerator internals: transport, row buffers, taps, lanes, reducer, writeback](Accelerator/Accelerator%20Blocks.canvas)
- [One engine's submodules](Accelerator/Engine/SAD%20Engine%20Blocks.canvas)
- [Testbench guide](Verification/Testbench%20Guide.md)
- [Synthesizable SystemVerilog modules](rtl/)
- [Interface contract](System/Interface%20Contract.md)
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
python scripts/run_tests.py --suite engine --case 11:8 --vcd
python scripts/run_tests.py --suite comparator --case 32:15 --vcd
python scripts/run_tests.py --suite shift --case 11:8:32 --vcd
```

Windows may alternatively use the local, untracked portable installation at `tools/mingw64/bin/`. No third-party Python packages are required by these tests. Standalone SV benches are tracked in `tests/rtl/`. Compiled simulations, optional waveforms and legacy vectors are generated in `build/`; results go to `sim/results.txt`. See the testbench guide for parameter matrices and extra seeds.

GitHub Actions reruns all checks for every push and pull request. Simulation output is available as a workflow artifact. Cloud CI does not run Quartus or board hardware tests. Every new functional RTL module must arrive with its code-adjacent walkthrough and standalone self-checking bench, registered in the runner; `check_walkthrough.py` rejects missing coverage.

### Open in Obsidian

Choose **Open folder as vault** and select the repository root. Start at **Home** and follow the linked spine: **System Architecture** → **Accelerator Architecture** → **Stereo Frontend** / **SAD Engine Architecture** → individual modules and **Verification Map**. The same levels are nested in `System/`, `Accelerator/Frontend/`, `Accelerator/Engine/`, and `Verification/`. Folders do not create Obsidian Graph links by themselves; the hub notes do. The root **Architecture.canvas** remains a broad note map; the drill-down canvases are alongside their level's notes. No community plugins are required. Personal workspace layout is not committed.

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

[[Module Blocks.canvas]] is the planned *system* wiring; [[Accelerator Blocks.canvas]] is the planned *accelerator* hierarchy, with [[SAD Engine Blocks.canvas]] for the implemented single-lane wrapper. Ethernet packet staging and VGA display are optional and unimplemented here. `P_LANES` is a compile-time design choice: 32 lanes over disparities 0–31 is one single-pass example, while fewer lanes over a larger range require repeated groups and best-state merging.
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
System/                         whole-system canvas, CPU, hardware and interface contract
Accelerator/                    accelerator schematic, bank, reducer and timing
Accelerator/Frontend/           stereo frontend canvas and row-buffer walkthrough
Accelerator/Engine/             engine canvas, RTL walkthroughs and SAD mathematics
Verification/                   evidence, testbench guide and graph hub
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
