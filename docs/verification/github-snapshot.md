# GitHub snapshot verification — 2026-11-20

This record covers the current **work-in-progress compute datapath snapshot**, not a completed autonomous accelerator or board system. The teammate handoff is [here](../team-handoff.md). Historical experiment logs remain distinguished from these publication-time reruns.

## Completed publication-time checks

- Exact-source walkthrough coverage: **13 functional modules passed**; the fixed synthesis-smoke wrapper is the documented exception.
- Canonical sensitivity rerun: **38 RTL mutants detected**, **nine spare-row guard violations rejected**, plus a positive integrated baseline, **five bad-caller schedules** and **four additional RTL mutants** rejected. Caller-monitor checks are not synthesized protection.
- Teaching lab: seven directed delay beats, two deliberately faulty teaching designs rejected, and seven module examples with 40 checked stimulus edges passed.
- Independent v2 replay rerun: Python oracle self-check and all three existing cases passed, with 222, 394 and 249 mature observations respectively. This rerun is not a new blind test-author experiment and does not repeat the historical independent mutation challenge.
- Publication audit: seven canvases parsed with valid file/edge references; ordinary relative Markdown links and wiki links resolved. No detected token/private-key signatures in the scoped public files. This is a bounded check, not a guarantee against every possible secret format.
- Real functional RTL remained unchanged during publication preparation; only status/handoff documentation and explanatory whitespace were adjusted.

## Full canonical regression

The default full command `python scripts/run_tests.py` **passed with exit zero** and the actual final marker:

```text
PASS: 152 simulation cases completed; suite=all.
```

No reduced matrix, random-cycle override or extended timeout was used. The completed run includes the final audit-only store-bench extension, the ten-case controller-emulated integration matrix, all spare-row additions and the six legacy reference configurations. The production-width packed `K=11/P=8/W=640/H=41/T=32/S=1` case reports 23,936 checked outputs; its direct-column backend counterpart uses 38 rows. These do not establish 480-row packed end-to-end or board performance.

All five publication-check stages (walkthrough, full regression, sensitivity, teaching and independent replay) returned zero. The full regression took 1,693.77 seconds on this Windows/Icarus environment. A final fingerprint check confirms all fourteen real RTL files remained unchanged through the checks. Frozen independent test-author sources were also preserved; this publication adds no new test experiment or functional HDL.

## Fresh Quartus Analysis & Synthesis

Actual Quartus Lite **22.1std.0 Build 915**, Cyclone IV E, `K=11`, 8-bit pixels, width 640:

| Top | Configuration | Result | Logic elements | Registers | Embedded memory bits | RAM nodes |
|---|---|---|---:|---:|---:|---:|
| `stereo_sad_datapath` | 32 lanes, one spare row, 12 row banks per image | PASS | 30,274 | 15,519 | 122,880 | 24 |
| `circular_row_buffer` | Separate serial reference path, 11 active row banks | PASS | 697 | 33 | 56,320 | 11 |

Commands:

```sh
python scripts/check_row_buffer_synthesis.py --quartus-map /path/to/quartus_map --top datapath --taps 32 --timeout 600
python scripts/check_row_buffer_synthesis.py --quartus-map /path/to/quartus_map --top streaming --timeout 600
```

Use the actual installed executable path (`quartus_map.exe` on Windows). Both runs returned zero, mapped the expected pixel memory and had no errors. Both warned that only one processor was selected; the compute top additionally warned about constant output pins. These warnings are recorded, not suppressed. The helper validates the expected embedded pixel-memory capacity; these are not logic-only smoke results.

**Not run or established:** Quartus fitting, TimeQuest timing, native Questa reruns for this publication, SDRAM/Avalon/Nios V integration, autonomous controller implementation, board tests or sustained throughput.

## GitHub and evidence boundaries

GitHub Actions supplies the public canonical regression/sensitivity/teaching result and its uploaded simulation artifacts. Quartus and independent replay are local checks, not jobs in that workflow. Follow the workflow run for the actual published commit; local results do not imply a cloud pass.

Full local commands/logs, source fingerprints, Quartus generated projects and proof JSON are retained under ignored `build/github-snapshot/`, `build/datapath-synthesis/` and `build/row-buffer-synthesis/`. Personal Obsidian settings, machine-only Quartus GUI metadata, portable tool binaries, datasets, generated outputs and simulator transcripts are excluded from the snapshot. Source, tests, diagrams, specifications and status documents are published.
