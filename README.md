# Nios V Stereo Block-Matching Accelerator

[![RTL verification](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator/actions/workflows/rtl-tests.yml/badge.svg)](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator/actions/workflows/rtl-tests.yml)

SystemVerilog stereo SAD accelerator under incremental development for the **Terasic DE2-115 (Cyclone IV E, EP4CE115F29C7)**, with **Nios V** as the system-integration target. This repository doubles as an **Obsidian study/design vault**.

## What works now

- **Pipelined column-SAD calculator:** parallel unsigned absolute differences and a registered balanced reduction tree.
- **Circular column-history buffer:** retains K−1 column sums and a running total; includes the final window-SAD adder.
- **Single SAD engine:** connects those modules, accepting already-aligned vertical pixel columns and returning full K×K window costs.
- Defaults: **11×11** window, **8-bit** pixels. This is not yet a raw-image streaming frontend or a full disparity search.
- Three standalone self-checking SystemVerilog benches (calculator, buffer, engine), each tested in eight configurations, plus six independent Python/deque buffer cases: **30 passing simulation cases**.
- Four deliberate arithmetic/timing/flush/wiring faults were rejected by the testbenches.
- Engine Analysis & Synthesis passed in Quartus Prime Lite 22.1 with **zero errors and zero warnings**, reporting 770 logic elements before fitting. No fitted timing result is claimed.
- Linked architecture notes, an Obsidian canvas, and a complete line-by-line RTL walkthrough.

**Not implemented here yet:** image ingress/line buffers and disparity alignment, the 32-lane wrapper, comparator tree, runtime kernel configuration, Nios V/Avalon integration, or a board-ready bitstream. Prior notes record a separately demonstrated Nios V Hello World; its working board project is not included here.

## Start here

- [Project dashboard](Home.md)
- [Complete code and line-by-line explanation](Column%20Sum%20Buffer%20-%20Code%20Walkthrough.md)
- [Pipelined column calculator: code and explanation](Pipelined%20Column%20SAD%20Calculator.md)
- [Single engine: code, interfaces and row timing](Single%20SAD%20Engine.md)
- [Testbench guide](Testbench%20Guide.md)
- [Synthesizable SystemVerilog modules](rtl/)
- [Interface contract](Interface%20Contract.md)
- [Rolling SAD mathematics](Rolling%20SAD%20Math.md)
- [Verification](Verification.md)
- [Progress log](docs/progress.md)
- [GitHub update workflow](docs/github-workflow.md)

### Open in Quartus

Open **`Stereo_SAD_Engine.qpf`** for top-level `sad_engine`, or **`Stereo_SAD.qpf`** for the original buffer-only component. Keep companion `.qsf`, `constraints/`, and `rtl/` paths intact. Clock constraint: provisional 50 MHz.

This is an **Analysis & Synthesis component project**, not a board top-level. Physical pin assignments, external I/O timing, fitting, processor integration and programming are later gates.

### Run tests

Requirements: Python 3 and Icarus Verilog (`iverilog` and `vvp` on PATH).

```sh
# Ubuntu/Debian: sudo apt-get install iverilog
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py

# Individual stages or waveform output:
python scripts/run_tests.py --suite column
python scripts/run_tests.py --suite buffer
python scripts/run_tests.py --suite engine --case 11:8 --vcd
```

Windows may alternatively use the local, untracked portable installation at `tools/mingw64/bin/`. No third-party Python packages are required by these tests. Standalone SV benches are tracked in `tests/rtl/`. Compiled simulations, optional waveforms and legacy vectors are generated in `build/`; results go to `sim/results.txt`. See the testbench guide for parameter matrices and extra seeds.

GitHub Actions reruns all checks for every push and pull request. Simulation output is available as a workflow artifact. Cloud CI does not run Quartus or board hardware tests.

### Open in Obsidian

Choose **Open folder as vault** and select the repository root. Open **Home** or **Architecture.canvas**. Use the built-in Graph view to navigate linked notes. No community plugins are required. Personal workspace layout is not committed.

## Architecture direction

```text
Rectified grayscale stereo images
    → image/line buffers
    → parallel disparity lanes (planned: 32)
        → column_sad (implemented: pipelined differences and column sum)
        → column_sum_buffer (implemented: history and final window adder)
        [one integrated sad_engine is implemented and tested]
    → pipelined minimum-SAD/disparity tree
    → disparity output
```

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
rtl/               implemented SystemVerilog components
scripts/           HDL test runner and documentation consistency check
constraints/       component timing constraints
Stereo_SAD*.qpf/qsf Quartus buffer and engine component projects
*.md               linked Obsidian design and study notes
Architecture.canvas visual architecture navigation
.github/workflows/ automatic RTL checks
hardware/          preserved board-system integration placeholder
software/          preserved Nios V software planning
tests/rtl/         tracked standalone self-checking SV benches
tests/README.md    current tests and preserved future system-test plan
docs/             feasibility reports, diagrams and progress
tools/            tracked report-generation scripts (portable binaries ignored)
```

## Progress and publishing

This repository is **public**. Only project material belongs here; no credentials, private correspondence, datasets, tool binaries or generated Quartus databases.

During assisted development, completed milestones are tested, documented, committed and pushed. GitHub then runs CI automatically. This is **not an unattended local file watcher**: manual edits remain local until explicitly committed and pushed. See [the workflow](docs/github-workflow.md).
