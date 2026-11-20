# Stereo SAD FPGA

**DE2-115 · SystemVerilog · Nios V integration target**

## Start here

| I want to… | Open |
|---|---|
| Share the current project with teammates | [[docs/team-handoff|Teammate handoff]] |
| Understand the whole project | [[System Architecture]] |
| See what is built and what comes next | [[Project Plan]] |
| Study modules, ports and clock timing | [[Datapath Study Guide]] |
| Write and run a small testbench | [[Hands-on Testbench Lab]] |
| Check evidence and remaining gaps | [[Integration Readiness]] · [[Verification]] |

## Current checkpoint

The **packed-load frontend and full fixed-search compute datapath are implemented**: spare-row storage → aligned columns → SAD engines → tagged minimum-cost/disparity output. Readiness, row ownership and no-copy bank promotion remain caller-controlled.

**Next: interactive module-by-module simplification review and control planning.** A central FSM with distributed local controllers is the direction; one controller covers each complete PE. No controller RTL or visual Quartus design files exist yet. CPU/SDRAM transport, fitted timing and board integration are not established. The user has authorized sharing the current project snapshot, not marking these gates complete.

## Architecture and explanations

**[[System Architecture]] → [[Accelerator Architecture]] → [[Stereo Frontend]] / [[SAD Engine Architecture]] → module explanations.** These links create the Obsidian Graph hierarchy; folders alone do not.

Open [[Architecture.canvas|the note map]] or follow the subsystem hubs for their block canvases. The study guide is the module/source/bench index; Home does not duplicate that catalogue.

## Plans, evidence and history

- **Intended system:** [[Paper Design Plan.canvas|Original accelerator plan]] · [[Paper System Plan.canvas|Original whole-system plan]]. Preserved designs, not implementation evidence.
- **Checks:** [[Verification Map]] · [[Testbench Guide]] · [[Control Emulation|whole-path control-emulation tests]]. Current and historical evidence are separated in [[Verification]].
- **Records:** [[docs/progress|Progress log]] · [[docs/resources|Resources]] · [[docs/github-workflow|Publishing workflow]].

[GitHub repository](https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator)

## Using the vault

The repository root is also the vault root. Follow the hub links above or open Graph with Ctrl+G. Historical audits remain linked and labelled. No community plugins are required. Recent personal bookmarks, search/Graph filters, appearance and local navigation CSS changes are not published; teammates can choose their own settings without changing the project sources or diagrams.
