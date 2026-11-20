# Progress log

## 2026-11-20 — current project snapshot authorized for teammate sharing

- The user explicitly requested publication of current progress and project state to the existing public GitHub repository. This supersedes the earlier publication pauses below, not the unfinished interactive review or hardware-control/system gates.
- Added a [teammate handoff](team-handoff.md) covering implemented hardware, reading order, reproducible commands and remaining work. README, Home, the active plan and readiness index now distinguish snapshot publication from completion of the accelerator.
- Recorded the current control direction: central coordination plus distributed local controllers, **one controller per complete PE**, with shared L/R scanning. Quartus `.smf`/`.bdf` views are options under discussion, not files or controller RTL delivered by this snapshot.
- **All 152 default regression cases pass with the final current benches**, without reduced geometry, random-cycle overrides or an extended timeout. Fresh exact-source coverage, canonical fault/guard checks, teaching tests and the existing three-case independent v2 replay also pass. Fresh real Quartus A&S again maps the complete 32-lane compute top to **30,274 LE / 15,519 registers / 122,880 memory bits / 24 M9K nodes**, and the separate serial reference to **697 LE / 33 registers / 56,320 bits / 11 M9K nodes**. Warnings and verification limits are recorded, not suppressed. See the [publication-time verification record](verification/github-snapshot.md) for exact scope; this fresh full run is distinct from historical reduced-smoke evidence.
- Retained all functional RTL and frozen independent-test sources unchanged during publication preparation. Reviewed the scoped source/test/documentation diff and preserved personal Obsidian settings, machine-only GUI metadata and unrelated local work outside the commit. Seven canvases and their referenced files/edges, ordinary Markdown links and wiki links pass the publication audit. Build logs, generated projects, portable tool binaries and simulator transcripts remain local.
- This is **not** an autonomous-controller, Nios V/SDRAM transport, fitted-timing, board or throughput milestone. GitHub Actions remains separate cloud evidence and must be checked for the actual published commit.

The entries below are preserved historical checkpoints; their original no-publish and verification limitations are not retroactively rewritten.

## Independent coverage repair — separately frozen v2, no publishing

- At the user's request, a fresh follow-up author strengthened inactive left/right load data symmetrically using full-word complements. Valid-side data, idle payloads, RNG sequence, ownership/scheduling, images, expected results, raw SAD oracle and SV checker are unchanged. Added Python self-checks for all validity combinations, full/partial words and P=1/P=5.
- All three real-DUT configurations still pass with 865 mature winners and byte-identical observations. All five original compiled blind mutations are now rejected, including the previously escaping right-write-enable miswire; an explicitly non-blind mirrored left-enable fault is also caught. The history assertion-isolation experiment again confirms independent scoreboard rejection with a passing disposable baseline.
- Self-removing ad-hoc verification compares every v1/v2 vector field and preserves all original v1 evidence/source fingerprints. New evidence is under `build/independent-control-validation-v2/`. Fresh ten-case control, 21-case reduced all-suite, 13 walkthrough mappings and canonical sensitivity/guard checks pass. All fourteen real RTL files remain unchanged; no full-default-suite, synthesis, native/board or CI claim.
- [Versioned evidence and limitations](../Verification/Independent%20Control%20Validation.md). This is a deliberate post-challenge refinement, not a newly blind experiment. No staging, commit or push.

## Original independent test authoring — frozen v1, no publishing

- A fresh isolated author wrote `tests/independent_control/` from the functional contract/public declarations without reading RTL bodies, existing tests or prior results. A second isolated author supplied five blind mutations from RTL without reading tests. Same configured model family; context isolation reduces confirmation bias, not a zero-bias guarantee.
- Froze all three test files before first RTL simulation and kept them unchanged. All three bounded Icarus configurations pass: 3,649 replay edges, 865 mature winner observations, 7,121 pre/post-edge checker calls. This is a standalone cross-check, not canonical-runner/CI registration or a new whole-default-suite result.
- Four of five compiled blind faults are rejected. The right-history fault initially hits an RTL assertion; an assertion-isolated disposable baseline still passes, and its history mutant independently fails the raw-image scoreboard. The right-write-enable miswire survives all three cases because invalid-side data remains correct; the coverage gap is retained, not patched away after observing results.
- Self-removing ad-hoc verification checks original logs, survivor masking, source fingerprints and the assertion-isolation experiment. All fourteen real RTL files and frozen authored tests remain unchanged. [Evidence, exact cases, reproduction and limits](../Verification/Independent%20Control%20Validation.md). No staging, commit, push, new synthesis or board claim.

## Single-pulse abort/restart coverage follow-up — simulation only, no publishing

- Independent review identified a masking gap: the first bench cleared again before each restarted frame. A compiled mutant that ignores backend frame-clear while frontend data is valid demonstrably passed that old bench; this was a coverage defect, not a demonstrated defect in the real RTL.
- Each abort now requires an in-flight winner, checks `LAT+2` clear-deasserted/reset-released quiet edges, and reloads/restarts without a second clear. A separate guard and accepted-read counter require both actual single-pulse restarts. The frame-clear abort is issued after the frontend handoff has had time to reach arithmetic when row width permits.
- The strengthened ten-case control matrix, H<K, P=16/S=5, and VCD case pass, as does the 21-case reduced all-suite smoke. Five caller faults and four compiled RTL mutants are rejected; the formerly escaping mutant now produces a forbidden ghost result during the quiet interval. Read-only independent follow-up found the masking gap closed and no correctness regression.
- The strengthened K=11/P=8/W=640/T=32/S=1/H=13 simulation passes directly with exit 0, 5,378 checked records, two single-pulse restarts and 28 quiet edges. Its earlier Python-runner command reported an anomalous negative timeout; the failed report and successful direct-runtime output are preserved separately. The fourteen current control reports total 26,344 records, 24 single-pulse restarts and 226 quiet edges; the earlier checkpoint below is historical.
- Fresh evidence and limits are linked in [Control Emulation](../Verification/Control%20Emulation.md#independent-review-follow-up-single-pulse-abortrestart). No functional RTL edits, staging, commit or push.

## Initial control-emulated whole-datapath checkpoint — before the single-pulse follow-up

- Added `tests/rtl/tb_stereo_control.sv`: test-only row/frame caller around the real complete compute top, independent accepted-port L/R word/owner monitor, full raw-pixel K×K winner oracle, exact consumer-edge checks and CSV framebuffer sink. No controller RTL, FIFO, transport, source-module or project-constraint changes.
- All ten default control configurations and four targeted cases pass. The combined K=11/P=8/W=640/T=32/S=1 **13-row** case passes with four completed jobs, two aborts and 5,378 captured checked records; repeated ring wraps are covered separately in longer matrix cases. Extra tests cover H<K, 16-bit pixels, five spares, a second seed and an actual VCD. [Contract, results and limits](../Verification/Control%20Emulation.md).
- New sensitivity checker proves a positive baseline, rejects five bad caller schedules and catches three compiled RTL wiring mutants. Registered it in the canonical sensitivity command; all 38 earlier mutants and nine real-DUT guards pass again. Caller-monitor checks are not synthesized protection.
- All-suite reduced smoke (`--case 3:8 --random-cycles 0`) passes 21 cases; all 13 exact-source mappings pass. CSV readback independently checks 26,348 records across the ten matrix plus four targeted cases. Fourteen RTL fingerprints remain unchanged.
- Native Questa compilation is clean (zero errors/warnings). Runtime is again licence-blocked by the user's existing node-locked instance, which was not closed. No native simulation, new synthesis, fitted timing, board or achieved-throughput claim.
- The earlier background full-default rerun timed out at 600 seconds in the existing wide packed 32-lane reference. Neither the new control matrix nor the reduced smoke is relabelled a complete default-suite pass. No staging, commit or push; existing unrelated edits remain intact.

## Vault navigation cleanup — local documentation only

- Simplified `Home.md` into the current reading route; native Obsidian bookmarks point to the system, accelerator, frontend, engine, study and verification hubs.
- Updated the active plan, readiness/verification hubs, component navigation prose and learning introductions to distinguish implemented packed-store → fixed search → winner computation from missing autonomous control and board transport. Learning checkboxes remain the user's, not an implementation checklist.
- Preserved the former serial-stage audit in `Verification/Archive/Integration Audit - Serial Baseline.md`; its historical scope is explicit, while `Verification/Integration Readiness.md` now describes current readiness.
- Corrected stale current-canvas labels and marked recovered paper designs as historical snapshots. No node positions/sizes, connections, source RTL, benches or project constraints were changed by this cleanup.
- Kept generated folders out of Obsidian search and the historical audit out of the default Graph view. No community plugins, workspace reset, backup deletion, staging, commit or push.
- Local before-copies and cleanup/check output live under ignored `build/vault-tidy/`. This is not a new native Questa, Quartus, fitted-timing or board-verification milestone.

## Current increment — parameterized spare-row prefetch; no publishing

- User requested at least one spare row with a parameter for additional headroom. `SPARE_ROWS=1` propagates through the packed store/frontend/complete top; bank widths and rotation cover K+SPARE_ROWS banks while columns stay K pixels wide. Active-bank read gating permits same-word-address spare writes. No row copies, FIFO, new functional module or latency change.
- Standalone storage prefetches/replays the complete intact active window; the actual left-delay/right-cache bench checks taps, tags, bubbles/clears and delayed independent L/R arrivals. Complete compute tests consume future rows prefetched during the preceding scan, without between-row reload. S=2/3 matrix additions and independent-seed S=5/6 cases pass. Readiness/promotion across bubbles remain caller-owned, not a synthesized controller.
- Before the final audit-only bench extension, all **142 default regression cases**, 13 exact-source mappings, 38 compiled mutants and nine parameter/address/active-bank guard cases passed. RTL hashes still match synthesis manifests. [Current evidence and limits](verification/spare-row-prefetch.md) distinguish the later targeted follow-up from that whole-suite checkpoint.
- Final independent red-team: conditional acceptance/no concrete RTL defect. Its partial right-row concern is resolved by the existing caller completion gate and fresh W=5/9 cases. Added store-only back-to-back accepted-read bank rotations; fresh **ad-hoc verification passes 14 real-DUT cases**, all 38 mutants and nine guards. RTL is unchanged. No new whole-suite/native/fitted/board result; temporary harness removed.
- The initial advocate/skeptic/evidence reports have now arrived and are reconciled against their earlier K-only baseline. They support the minimal contiguous ring subject to the stated contract; do not read historical test gaps as new implementation defects. One extra **ad-hoc** experiment confirms that the compiled registered-oldest read-gating mutant is rejected while the actual store passes. No RTL change; ordered successor promotion and whole-active-row protection remain explicit. [Council reconciliation](verification/spare-row-prefetch.md#returned-initial-council--reconciliation-against-the-implementation).
- Actual K=11/P=8/W=640/S=1 Quartus A&S: packed store 632 LE/8 registers/61,440 memory bits/12 M9K; frontend with 32 taps 4,264 LE/2,985 registers/122,880 bits/24 M9K; complete 32-lane top 30,274 LE/15,519 registers/122,880 bits/24 M9K. Additional S=2 store: 1,091 LE/8 registers/66,560 bits/13 M9K. All zero errors; one processor warning each, plus constant-record-pin warning on the top. No fitted timing/throughput/board claim.
- Native Questa compilation before the audit-only bench extension passed with zero errors/warnings. All three runtime attempts were license-blocked by the existing user session, which was left running. The extended store bench is verified with Icarus, not freshly with native Questa.
- Exact RTL walkthroughs, current contracts and hierarchy links are synchronized. Interactive module review resumes after verification; **no commits, pushes or unrelated worktree cleanup** in this increment. Earlier sections below are historical.

## Previous milestone — complete compute datapath; review before publishing

- Independent advocate, skeptic and evidence/feasibility reviews conditionally chose two cohesive additions. [Frozen contract](accelerator-datapath-spec.md): exact timing, common-interior/all-lane qualification, prefix-only lane warmup, clear scope and 32-bit packing, resolved before RTL.
- Added `sad_search_backend`: existing engines + existing comparator + full-search qualification and winner tags. Added `stereo_sad_datapath`: real packed frontend composition + combinational zero-on-invalid record. No controller, FIFO, replay/group logic or duplicated arithmetic.
- Each has a standalone raw-pixel-window bench and an exact-source, line-explained walkthrough, registered in the checker. Updated architecture/study/verification links. Thirteen source/walkthrough checks and 33 production-fault rejections pass.
- Nine additional boundary/seed cases pass, including K=3/W=64/five lanes through all 480 rows. A 10-bit-pixel complete-path case also passes. Native Questa compilation passes for both benches; runtime is blocked by the user's existing one-session node-locked license, which was not disturbed. Simulation passes are Icarus.
- Initial default run timed out in the full-width 32-lane raw reference, without a numerical mismatch. Caching immutable fixture pixels removes repeated hash generation, not the independent K×K sums. **The final full default rerun passes all 130 cases**, including production-width 32-lane and odd-width paths. No coverage was reduced; 12 additional real-DUT cached/uncached reference simulations agree exactly.
- Actual K=11/P=8/W=640 integrated A&S passes for 1/3/32 lanes: 2,715/4,525/30,537 LE and 755/1,724/15,519 registers; each retains 112,640 memory bits and 22 M9K nodes, zero errors/two warnings. Different search ranges, not equivalent-search speedup evidence; no fitting/TimeQuest/board claim.
- Fresh self-removing verification harness passes source/walkthrough and 33 fault checks, 12 cached/uncached reference simulations, oversized-record rejection and synthesis/source hashes. Evidence: `build/compute-final-check/evidence.json`; full report: `build/compute-regression-results.txt`. No functional source changed during this verification.
- [Observed evidence and limits](verification/compute-datapath.md). Interactive simplification review precedes **any commit or push**. Controller work remains last. Older sections below are historical, not current status overrides.

## Previous milestone — packed-load frontend datapath (14 November 2026)

- [x] User reviewed the serial row-storage block and authorized the next datapath block, with controllers explicitly deferred.
- [x] Freeze independent four-pixel word loads, shared explicit column reads, row-bank lifetime obligations, scoped clears and two registered metadata handoffs in `docs/packed-frontend-contract.md`.
- [x] Implement the independently addressed word RAM, packed row-store datapath and stereo frontend using the existing left delay/right cache; no FIFO, ownership FSM, refill controller or central controller.
- [x] Deliver each new RTL block with an exact-source walkthrough, standalone raw-data scoreboard and test-runner registration. Existing serial-reference modules and lessons remain separate, not extra buffers in the new path.
- [x] Add word-address/lane/bank-tag/load-clear and frontend tag/row-clear/LR-wiring fault-sensitivity checks; all 26 current mutants are rejected.
- [x] Initial lightweight council review followed by three independent read-only draft reviews, now reconciled in `docs/verification/packed-frontend-council.md`. All conditionally support the shallow boundaries; protocol, ownership and full-height coverage limits remain explicit. Select pixels before rotating rows rather than adding modules/FIFOs. Parent-measured store logic drops 2,633→879 LE and full frontend 8,061→4,546 LE without changing interface latency or memory.
- [x] Final-source gates: all 110 simulation cases, 26 targeted faults, 11 exact-source mappings and separate teaching checks pass. Default packed/store frontend Analysis & Synthesis passes, with 11/22 M9K RAM nodes respectively; hashes match current RTL. Fresh native compilation passes; runtime is license-blocked, not a native simulation pass. See `docs/verification/packed-frontend.md`.
- [ ] User review of this frontend before the next engine-bank block or publication. Native Questa simulation remains subject to the existing one-session license; do not close the user's running session.

## Previous milestone — row-storage block, reviewed (14 November 2026)

- [x] Preserve the existing row-buffer ports and output edge while replacing asynchronous pixel reads with clocked RAM-bank instances, captured slot tags and a newest-pixel bypass.
- [x] Deliver the internal `row_ram_bank` with its own exact-source/code-adjacent walkthrough and registered self-checking bench; eight standalone bank cases pass before the ten parent row cases.
- [x] Check real 640×480 and odd-width 641×480 streams, clear/restart, bubbles and before/after-edge output stability using an independent flat-image reference.
- [x] Run all 80 regression cases, all 16 targeted production-fault checks, both teaching baselines and the two separate teaching fault checks successfully under Icarus; all eight RTL source walkthroughs match.
- [x] Full default K=11 / P=8 / IMG_W=640 Analysis & Synthesis: 697 logic elements, 33 registers, 56,320 logical memory bits, and 11 M9K RAM nodes. The isolated one-processor guard has one processor-count warning and no errors; this is not fitting, fMAX or board proof. Retain source hashes and logs under `build/row-buffer-synthesis/`; see `docs/verification/row-buffer-synthesis.md`.
- [x] Compile current sources and benches with native Questa. Fresh simulation is blocked by the existing user's node-locked session; do not close it or count an old simulation as a current pass.
- [x] User code review/questions complete; next packed-load/frontend datapath authorized. Publication remains deferred until review of the new block. Controllers remain a separate later phase.

## Previous milestone — component integration-readiness audit (14 November 2026)

- [x] Inspect the seven functional RTL modules and existing integration boundaries against the original paper plan; distinguish the implemented engine and column-pairing connections from the absent complete frontend/bank/system.
- [x] Fresh canonical checks: all seven exact-source walkthroughs, 70 simulation cases and 12 production-fault rejection checks pass.
- [x] Fresh isolated Quartus Lite 22.1 Analysis & Synthesis: calculator, column history, engine, left delay, 32-tap right cache, 32-lane comparator component and width-16 row-buffer smoke all pass with zero errors/warnings. The bounded width-640 retry did not finish within 120 seconds; no full-width synthesis pass is claimed.
- [x] Fresh native Questa Intel Starter FPGA Edition 2021.2: all **66 simulations passed** (64 SV parameter cases, 2000 random cycles each, plus two teaching benches). Verify per-case scoreboard PASS markers, the complete case list and unchanged RTL source hashes; retain transcript/JSON evidence under `build/integration-audit-gc24o2mc/questa-verified/`.
- [x] Add [[Integration Readiness]] with port/width ownership, registered handoffs, derived timing, border/drain rules, requirement status and raw evidence locations. Extend the single [[Project Plan]] with gated deliverables and the proposed frontend pre-RTL checklist.
- [x] Reconcile independent read-only reviews with the fresh tool evidence: keep Nios V/SDRAM proof as a parallel immediate system track, require at least three measured lane-count builds, add production-width simulation to the storage gate, and make registered row-end ingress timing and comparator width propagation explicit. Older directed-only Questa observations are superseded by this audit's actual 66-case run.
- [ ] Implement the frontend, row/controller vertical slice, practical full-width row storage and bank/reducer wiring as separate verified milestones. This audit changes no functional RTL or original paper canvases.
- [ ] Fitting/TimeQuest, Avalon/SDRAM/CSR/Nios V integration and board/end-to-end performance remain unverified. Keep publication scoped to verified assisted work; preserve unrelated pre-existing staged/local edits rather than bundling them into the audit.

## Previous milestone — focused Obsidian vault cleanup

- [x] Consolidate future frontend, disparity-bank, controller, transport and Nios V/board work in [[Project Plan]], preserving the detailed design/feasibility reports as supporting references.
- [x] Remove six separate placeholder/redundant notes: Nios V Interface, Hardware Integration, Interface Contract, Disparity Bank, Image Line Buffers and Column SAD Engines. Preserve useful buffer port/reset/clear rules in [[Column Sum Buffer#Interface contract|the implemented buffer explanation]].
- [x] Simplify [[Home]], hub navigation and five canvases; retain the system → accelerator → frontend/engine → implemented-module hierarchy. Replace speculative repeated blocks with links into the main plan and correct stale left-delay/right-cache status.
- [x] Exclude generated build/tool copies from Obsidian search/graph. Add the native `vault-navigation` CSS snippet for a source-preserving file-tree filter; no community plugin or source deletion.
- [x] Validate the working vault: 40 Markdown notes, 323 wiki references, 90 relative Markdown links, 39 canvas nodes and 33 edges; no unresolved targets/headings or dangling endpoints. Missing-target and missing-heading negative checks also pass. The pre-existing `sim/results.txt` link remains a local generated report, not a committed artifact.
- [x] Preserve every retained SystemVerilog study block byte-for-byte after newline normalization; all seven exact-source walkthrough checks, 70 simulation cases and 12 production-fault checks pass again. No RTL, tests or synthesis project changes belong to this cleanup.
- [x] Inspect the actual Home page and accelerator canvas in Obsidian. Native CSS is configured, but the already-open main window did not hot-load it during inspection; reload Obsidian to apply the optional file-tree filter. Do not claim a visually filtered tree before that reload.
- Existing unrelated local note formatting, graph settings and `Stereo_SAD.qsf` edits are not part of this publication. No new synthesis, fitted timing or board result is claimed.

## Previous milestone — module-by-module datapath study guide

- [x] Deliver [[Datapath Study Guide]] as one connected course covering all seven implemented functional modules, linked exact-source walkthroughs, ports/widths, state updates, warmup, nonblocking timing, independent references, test plans and implementation limits.
- [x] Add `tests/lab/tb_datapath_examples.sv`: small independent experiments, not a new functional wrapper; verify 40 stimulus edges with explicit row/tap, arithmetic, window, engine-pipeline and comparator expectations in Icarus.
- [x] Extend the teaching runner with `--examples`, keep separate example logs/waves, and register it in the teaching CI step. Extend the Questa macro with `part=examples`.
- [x] Correct the earlier three-lane comparator toy IDs to values fitting its two-bit default ID width; explain global-ID width requirements.
- [x] Exercise the 40-edge worked trace in Questa Intel Starter Edition 2021.2 as well as Icarus; both pass. Re-run all 70 production cases, 12 production fault checks, two beginner-lab faults and all eight per-module commands printed in the guide.
- [x] Record [actual guide/lesson verification](verification/datapath-study-guide.md) and connect the guide through the Home, accelerator and verification hubs without editing the user's canvases or local settings.
- [ ] User works through each component's own bench-writing exercises. Metadata, border policy, drain/clear scope, frontend/bank/top-level implementation and board acceptance remain future gates.
- No synthesizable datapath RTL or Quartus project is changed by this study-guide milestone; no new synthesis/fitted timing/board claim.

## Previous milestone — left delay, pairing verification and hands-on testbench lab

- [x] Implement `rtl/left_column_delay.sv`: one whole-column sampling register, registered valid, pause hold and synchronous reset/clear priority.
- [x] Deliver exact-code [[Left Column Delay]] walkthrough and independently scored `tb_left_column_delay.sv`; verify standalone before local pairing.
- [x] Verify delay/cache pairing after registration and at the next consumer edge in `tb_column_pairing.sv`; no new functional wrapper.
- [x] Run 70 full regression cases and 12 production fault checks. Teaching baseline: seven directed beats; two compiled DUT faults detected without editing real RTL.
- [x] Quartus Lite 22.1 Analysis & Synthesis: zero errors/warnings and 90 logic cells before fitting. [Evidence](verification/left-delay-synthesis.md).
- [x] Prepare [[Hands-on Testbench Lab]], editable scratch-copy workflow, standalone teaching bench, Icarus helper and Questa macro.
- [x] Actually exercise beginner lab and all eight macro-selected component/pairing cases in Questa Intel Starter Edition 2021.2.
- [ ] User works through individual bench-writing/part-testing sessions; then agree metadata/border/drain control and start frontend/bank/top-level wrapper. That hardware integration is not included here.

## Previous milestone — standalone right-column shift register

- [x] Implement `rtl/right_column_shift.sv`: shift whole K-pixel columns only on accepted input; registered taps have per-disparity warmup validity.
- [x] Preserve history across pauses, suppress bubble validity, and discard simultaneous input on reset/clear. Caller clears horizontal history between output rows.
- [x] Deliver [[Right Column Shift Register]] with exact source and sectionwise syntax/timing reasons, plus `tb_right_column_shift.sv` whose reference indexes an append-only accepted-column log.
- [x] Run eight shift cases, default full regression of 54 cases, and ten fault checks. Extra K=11/P=8/TAPS=32 run: seed 12345, 10000 random cycles, 8000 valid output beats; VCD generated locally.
- [x] Quartus Lite 22.1 Analysis & Synthesis of the full default component: 0 errors, 0 warnings, 2883 logic cells before fitting. [Evidence](verification/right-shift-synthesis.md).
- [ ] Implement matching left-column/valid alignment separately, then verify frontend pairing, coordinate/border policy and upstream drain timing. No bank or board claim.

## Previous milestone — standalone comparator tree

- [x] Implement `rtl/comparator_tree.sv` with a registered valid-aware minimum reduction over explicit `(SAD, disparity)` IDs; ties choose lower disparity.
- [x] Add exact-source [[Minimum Comparator Tree - Code Walkthrough]] and independently scored `tb_comparator_tree.sv`, including one/odd/32 lanes, bubbles and clear/reset.
- [x] Run five standalone SV suites and the Python reference: 46 simulation cases. Seven deliberate RTL faults were rejected, including reversed ties and invalid-lane selection.
- [x] Quartus Lite 22.1 Analysis & Synthesis of the default 32-lane component: 0 errors, 1 processor-count warning, 1622 logic cells before fitting. [Evidence](verification/comparator-synthesis.md).
- [ ] Feed the tree aligned, border-masked scores from a multi-lane bank and carry coordinate tags; not part of this standalone module.

## Vault hierarchy and HDL-module delivery rule

- [x] Organize study notes and drill-down canvases as system → accelerator → frontend/engine → module, with linked Obsidian hub notes. Preserve the root dashboard, project files, HDL, and existing code walkthroughs.
- [x] Update the note map and relative links; check wiki/Markdown targets and canvas file/edge references after relocation.
- [x] Require every new functional RTL module to register its exact-code walkthrough and standalone self-checking bench in the test runner. The existing synthesis-only smoke wrapper remains an explicit exception.
- [x] Run the 38-case RTL regression and five deliberate-fault checks; confirm an unregistered new RTL file is rejected.

## Previous documentation milestone — calculator, engine, and both circular buffers

- [x] Add code-adjacent explanations and Obsidian-rendered diagrams to [[Pipelined Column SAD Calculator]], [[Single SAD Engine]], [[Circular Row Buffer]], and [[Column Sum Buffer - Code Walkthrough]].
- [x] Distinguish the image-row ring from the per-engine column-history ring; document valid/bubble propagation, warmup, row drain, and stage boundaries.
- [x] Verify embedded RTL snapshots, the complete simulation regression, and deliberate-fault detection. This is documentation only; no new board/timing claim.

## Current milestone — circular row buffer

- [x] Implement `rtl/circular_row_buffer.sv`: one raster image, a ring of K rows, registered vertical column.
- [x] Keep disparity shift, pairing, border policy and engine drain outside this module.
- [x] Add `tb_circular_row_buffer.sv`. The reference is a flat image, not a copy of the ring.
- [x] Run eight `(K,P,W)` cases, including `K=1`, `IMG_W=1`, bubbles, clear-with-valid and random traffic.
- [x] Add the component-level canvas (subsequently split into system-level [[Module Blocks.canvas]] and [[Accelerator Blocks.canvas]] / [[Stereo Frontend Blocks.canvas]] drill-downs). Orange stages remain planned, not RTL.
- [ ] Connect two instances through a disparity tap and row-drain controller. Not this milestone.
- [x] Quartus smoke synthesis of `circular_row_buffer_synth` (`IMG_W=16`): 0 errors, 0 warnings, 3156 logic cells before fitting. The `IMG_W=640` default did not finish Analysis & Synthesis within 300 seconds.

## Previous milestone — pipelined calculator and single engine

- [x] Implement `rtl/column_sad.sv` with registered differences and balanced pipelined column reduction.
- [x] Add tracked standalone `tb_column_sad.sv` and `tb_column_sum_buffer.sv`.
- [x] Integrate `rtl/sad_engine.sv`; `tb_sad_engine.sv` independently recomputes full raw-pixel window SADs.
- [x] Run eight configurations for each standalone SV bench plus six original Python-reference cases (30 total).
- [x] Verify exact pipeline delay, bubbles, reset/clear priority, flushes, row drain/counts and no cross-row history.
- [x] Detect four deliberately introduced faults using the new benches.
- [x] Run an additional K=11/P=8 engine test with seed 12345, 5000 randomized cycles and VCD output.
- [x] Synthesize `Stereo_SAD_Engine.qpf` in Quartus Lite 22.1: zero errors, zero warnings, 770 logic elements before fitting.
- [x] Update study notes, source snapshots, architecture canvas and GitHub CI.

Evidence: [module/engine regression](verification/single-engine-simulation.txt), [extra seed](verification/single-engine-extra-seed.txt), [synthesis](verification/single-engine-synthesis.md).

No image-stream line buffer, disparity shifter, multi-lane bank, fitted Fmax or board integration is claimed.

## Previous component milestone — circular column history

- [x] Implement parameterized `rtl/column_sum_buffer.sv` for one disparity lane.
- [x] Verify six parameter configurations using Icarus Verilog 13.0 against an independent deque reference.
- [x] Verify warmup, wraps, bubbles, maximum/zero inputs, reset, clear and randomized traffic.
- [x] Add `Stereo_SAD.qpf` / `.qsf` for EP4CE115F29C7 and a provisional 50 MHz constraint.
- [x] Quartus Prime Lite 22.1 Analysis & Synthesis passed: zero errors, one processor-count warning. No fitted Fmax claimed.
- [x] Add the Obsidian dashboard, architecture canvas, interface notes and full code walkthrough.
- [x] Preserve prior repository history, system reports and diagram sources while making the working component the main entry point.
- [x] Add push/PR CI for simulation and embedded-source consistency.
- [x] Implement upstream column absolute differences and adder tree (completed in engine milestone).
- [x] Integrate one supplied-alignment SAD lane.
- [x] Implement the circular row-buffer abstraction (`rtl/circular_row_buffer.sv`). Disparity alignment is still open.
- [ ] Integrate parallel lanes and winner-take-all tree.

Evidence: [component simulation output](verification/column-buffer-simulation.txt), [test runner](../scripts/run_tests.py), [RTL](../rtl/column_sum_buffer.sv).

The component tests verify column-sum history, not raw-image stereo matching, CPU integration or board operation. The separate system-integration gates below remain open.

## Prior board bring-up (recorded before the component milestone)

- [x] Nios V processor instantiated for the DE2-115 project.
- [x] FPGA programming flow operational.
- [x] Nios V software build/download flow operational.
- [x] `Hello World` executed successfully.
- [x] JTAG UART output observed.

## Interpretation

This confirms the processor, clock/reset path, basic memory used by the application, BSP/application build, debugger/download path, and JTAG UART. It does **not yet prove external SDRAM sharing with a custom accelerator**.

## Immediate gate

- [ ] Verify CPU external-SDRAM read/write operation.
- [ ] Run walking-bit, address-pattern, and burst-sized memory tests.
- [ ] Add a custom accelerator control slave.
- [ ] Add a custom memory master.
- [ ] CPU writes a known input array to SDRAM.
- [ ] Accelerator reads, transforms, and writes it to another SDRAM region.
- [ ] CPU verifies every output word.
- [ ] Confirm cache flush/invalidate or use uncached buffers.
- [ ] Record total, active, read-stall, and write-stall cycles.

## Original stereo roadmap — historical checklist

- [ ] Freeze pixel format, border policy, tie rule, window size, and disparity range.
- [ ] Complete PC integer SAD reference.
- [ ] Generate tiny exact-disparity synthetic vectors.
- [x] Verify one supplied-alignment disparity lane in RTL simulation; pixel-column frontend still pending.
- [ ] Verify full winner-take-all output.
- [ ] Run one Middlebury pair end to end.
- [ ] Synthesize multiple disparity-lane configurations.
- [ ] Measure CPU-only and accelerated end-to-end cycles.
- [ ] Demonstrate continuous stored stereo pairs.
