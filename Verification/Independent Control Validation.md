# Independent Control Validation

[[Verification]] · [[Control Emulation]] · [[Stereo SAD Datapath]]

**Report scope:** the results and no-publish/full-suite limitations below describe the original v1 experiment and subsequent v2 repair checkpoint. The latest request authorizes publishing the current snapshot; it does not retroactively change those experiments. Historical raw logs and frozen v1 copies are local ignored build evidence, not files shipped in a clone. See the [teammate handoff](../docs/team-handoff.md) and progress log for publication-time checks. The frozen test-author README likewise records author-side checks, not the later parent-run DUT status.

## Current v2 — write-enable coverage gap closed

The user authorized a follow-up after the original blind challenge. A fresh follow-up author made the minimal symmetric stimulus change: on load operations, each invalid side now carries the full-word bitwise complement of its intended packed word. Valid-side data and idle zero data are unchanged. Python self-checks cover all four L/R validity combinations, full/partial words, P=1/P=5, bounded words and unchanged RNG state. **V2 is a deliberate post-challenge refinement, not a new blind experiment.**

V2 was separately frozen before its first RTL run. All three original baseline configurations still pass with the same 865 mature winners. Every control field, image, expected result and replay manifest matches v1; baseline `observed.csv` files are byte-identical. The original SV checker and raw-image oracle are unchanged. Only inactive-side data fields differ (54/252/135 changed words per side in the three configurations).

**All five original blind mutations are now rejected.** The previously surviving right-write-enable fault fails the independent raw-image scoreboard at `(0,0)`, expected SAD 0 versus observed 1. An additional explicitly non-blind symmetric left-write-enable mutation fails the same checker. Thus six compiled mutation variants are rejected, not six original blind challenges. The history fault's assertion-isolation experiment was repeated: the disposable assertion-free baseline passes and its mutant fails the independent scoreboard at `(5,2)`, expected SAD 0 versus observed 151.

The original v1 source files remain byte-for-byte under `build/independent-control-validation/frozen-v1-sources/tests/independent_control/`; original v1 reports, vectors, observations, mutation manifest and fingerprints were not overwritten. New fingerprints and all v2 execution, mutation, isolation and self-removing **ad-hoc verification** evidence are under `build/independent-control-validation-v2/`, especially `fix-evidence.json`. All fourteen real RTL files retain their original fingerprints.

Fresh surrounding checks also pass: the ten-case canonical control matrix, 21-case reduced all-suite smoke, thirteen exact-source walkthrough mappings, 38 canonical RTL mutants, nine parameter/address/active-bank guards, five bad-caller schedules and four canonical control mutants. This is not a new full default regression, native Questa, synthesis, board or CI result. No staging, commit or push.

## Original blind v1 — independence and frozen artifacts

A fresh isolated test-author instance received a neutral functional contract and could inspect only the complete top's public declarations (lines 1–41), not RTL bodies, existing tests, prior fixes or results. A second isolated instance read current RTL to author five blind semantic mutations, without seeing tests or prior reports. These are separate contexts using the configured model family, not evidence of a different model architecture or a guarantee of zero bias. Author-side Python checks did not simulate or compile RTL.

Before v1's first RTL compilation/simulation, the parent froze all three files under [tests/independent_control](../tests/independent_control/): `run_independent.py`, `tb_independent_replay.sv` and `README.md`. Their SHA-256 fingerprints are retained in `build/independent-control-validation/test-author-frozen.json`. No authored test source or expected result changed during that original experiment; its sources are now archived separately from current v2. The raw-image oracle does not import existing project tests, inspect DUT internals or reproduce rolling hardware state.

The standalone cross-check is deliberately separate from the canonical runner and CI. It adds no functional RTL or controller. Local simulator: Icarus. No new native Questa, synthesis, timing, board or CI result is claimed.

## Original v1 unchanged-DUT results

| Case | K / pixel bits / width / height / lanes / spares | Replay edges | Mature winners checked |
|---|---|---:|---:|
| `one_lane_k1` | 1 / 5 / 9 / 5 / 1 / 2 | 692 | 222 |
| `odd_k_lane_bank` | 3 / 8 / 17 / 9 / 3 / 2 | 1,762 | 394 |
| `power_lane_reuse` | 2 / 4 / 13 / 7 / 4 / 1 | 1,195 | 249 |

All three compile and report `INDEPENDENT_PASS`: **3,649 replay edges, 865 mature-result observations and 7,121 before-/after-edge checker calls**. Repeated windows, image fixtures and restarts are intentional; these are not 865 unique image coordinates or 7,121 independent test cases.

The cases exercise full raw K×K SAD comparisons, lowest-disparity ties at maximum cost, known shifts, independently randomized images, partial packed words, separate L/R readiness, spare prefetch and bank reuse, read bubbles, drained separate row clears, RAM-preserving row restart, reset/frame aborts at three offsets, quiet intervals and fresh-pixel restart. Both post-edge visibility and the following edge's synchronous consumer view are checked.

## Original v1 blind sensitivity: four rejections, one survivor

Each original challenge changes one unique anchor in its own disposable RTL copy. Compiler failures and timeouts are not detections. All four rejected variants reached simulation with compiled images.

| Deliberate defect | Observed result |
|---|---|
| Reverse four-pixel lane selection | Independent raw-image scoreboard rejects: expected SAD 0, observed 1 at `(8,0)`. |
| Advance right history during bubbles | Initially rejected by an existing backend protocol assertion. A separate assertion-isolation experiment below establishes independent scoreboard sensitivity too. |
| Prefer highest disparity on equal cost | Independent scoreboard rejects: expected cost 2295/disparity 0, observed cost 2295/disparity 2 at `(4,2)`. |
| Move winner x tag one edge early | Independent scoreboard rejects: expected `(2,0)`, observed `(3,0)`. |
| Drive right RAM write enable from left enable | **Survived all three frozen v1 cases. This historical coverage gap is closed in v2 above, not evidence that the defect is harmless.** |

### Existing-assertion dependence isolated

Only in disposable copies, the parent removed the backend's `synthesis translate_off` verification block from both a baseline and the history mutant. Functional backend logic and all frozen tests remained intact. All three baseline cases still pass. The history mutant then fails the independent raw-image scoreboard at `(5,2)`: expected cost 0/disparity 2, observed cost 151/disparity 2. This secondary diagnostic is separate from the original single-mutation experiment; it does not disable assertions in real RTL.

### Why the write-enable fault escapes

In v1, `run_independent.py` supplied both correct packed image words on every load operation, including a side whose valid bit was low. Every intended right word was therefore also present during a left-only load. The faulty enable could write the correct right data too early and omit the later right-only write without changing the eventual active window.

Read-only replay forensics compared right-word state under intended and faulty enables at every active-bank read: 234 / 1,656 / 786 read-word equality witnesses in the three cases. All three mutant `observed.csv` files are byte-identical to their corresponding baseline files. This analysis explains stimulus masking; it is not another hardware correctness oracle.

This motivated the user-authorized, **separately versioned v2** above. The original first-version sources and results were preserved before strengthening the stimulus; the historical failure was not relabelled as an original success.

## Reproduce and inspect

Run the current v2 standalone tests from the repository root:

```sh
python tests/independent_control/run_independent.py --self-check --rtl-dir rtl --out-dir build/independent-control-v2-rerun
```

The author's README documents individual cases, custom dimensions and executable overrides. The defaults use the local Windows `tools/mingw64/bin/{iverilog,vvp}.exe`; other installations must pass `--iverilog` and `--vvp` explicitly. Output folders must be under this repository's `build/`.

Retained **local generated evidence**, ignored by Git:

- `build/independent-control-challenge/mutations.json`: the blind author's five exact substitutions and assumptions.
- `build/independent-control-validation/baseline/`: per-case commands, raw image manifests, vectors, compile/simulation logs, observed outputs and summary.
- `build/independent-control-validation/mutants/`: original disposable sources and rejection/survival logs.
- `build/independent-control-validation/assertion-isolation/`: controlled assertion-isolation copies, exact commands and logs.
- `build/independent-control-validation/execution.json`: original process outcomes; nonzero exits remain explicitly unclassified there.
- `build/independent-control-validation/independent-evidence.json`: inspected classifications, counts, survivor forensics, isolation results and frozen-source fingerprints, produced by a successful self-removing **ad-hoc verification** script.
- `build/independent-control-validation/wrapper-unit-evidence.json`: thirteen explicit fixture-based unit checks of the mechanical execution wrapper; these are not HDL results.

All fourteen real RTL files retain their pre-authoring fingerprints. Earlier canonical walkthrough/sensitivity checks and the 21-case reduced all-suite smoke also pass; they are distinct from this independent three-case result. No new full default-suite pass is claimed. No staging, commit, push, or unrelated-worktree cleanup occurred.

## Limits

This bounded contract cross-check does not prove every parameter combination, production width/32-lane operation, a synthesized controller, illegal-caller protection, transport, backpressure or board behavior. Prefix-border arithmetic is not constrained beyond the supplied guaranteed common-interior contract. Frame/reset restarts rewrite complete windows; frame-clear RAM retention and physically suppressed coincident writes are not independently observed. V2 closes the observed write-enable mutation gap, not every possible coverage gap.
