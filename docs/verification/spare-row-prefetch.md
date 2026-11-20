# Spare-row prefetch — decision and verification ledger

[[Packed Circular Row Buffer]] · [[Stereo Frontend]] · [[Stereo SAD Datapath]] · [[Verification]]

## Decision brief (before RTL)

User request: parameterize extra prefetch storage with at least one spare row, then test it through the real shift register. Preserve the K active rows while the next rows load; rotate ownership without copying. No commits/publishing or controllers in this increment.

Alternatives: retain the old K-only destructive word refill; K+1 fixed banks; parameterized K+SPARE_ROWS contiguous ring; arbitrary bank-map/ownership FSM. Choose the parameterized contiguous ring conditionally on independent review and the tests below. The old K-only scheme cannot retain a whole active window while prefetching; fixed K+1 misses the requested knob; an arbitrary map/FSM is unnecessary for sequential row rotation.

Decisive criteria: active data remains intact, real embedded RAM, unchanged registered column/shift timing, K=1, non-power-of-two bank counts, raw-image verification and no new functional modules/FIFOs.

## Contract

- `SPARE_ROWS=1`, require `SPARE_ROWS>=1`. It is an elaboration-time parameter, not a runtime CSR.
- `ROW_BANKS=K+SPARE_ROWS`. Bank ports use `max(1,clog2(ROW_BANKS))`; the column remains K pixels wide.
- Accepted read: exactly the K banks `(read_oldest_i+j) modulo ROW_BANKS`, j=0..K-1, read the requested word. Spare banks do not read. Select lane before the K-pixel bank rotation; keep one-edge storage latency.
- Concurrent writes may target only spare banks. Identical word addresses in DIFFERENT banks are legal. An active-bank write during an accepted read is rejected in simulation, even at a different word address; the stronger contract keeps the active window intact. This assertion does not track ownership during read bubbles.
- Caller retains active-bank ownership across the entire row, including pauses, and tracks complete left AND right row readiness. A bank being physical storage is not evidence it is initialized. No ready signal, automatic warmup, ownership tracker or autonomous scheduling is added.
- For sequential frames, logical row r uses physical bank `r modulo ROW_BANKS`. At a boundary, drain the existing pipeline, clear horizontal history on a separate edge, require the next L/R rows complete, then advance oldest modulo ROW_BANKS. The immediate new row must occupy `(oldest+K) modulo ROW_BANKS`: extra spares provide ordered headroom, not arbitrary bank remapping. The retired oldest bank becomes spare; no row copy.
- A stalled/incomplete prefetch delays the next row. The frontend still scans columns left-to-right; right tap d remains R[x-d], with tap zero the newest accepted column. Prefetch does not shift columns or reset disparity history.
- Reset/frame clear suppress loads/reads and abort visibility, without erasing RAM. Row clear preserves RAM and accepts independent loads; the caller must still choose a safe bank.

## Independent review

Three read-only independent roles were dispatched before RTL: advocate, skeptic, evidence+feasibility auditor. Their reports have now been delivered and reconciled below. They inspected the earlier K-only baseline/proposal, not the completed implementation; their historical source references and evidence must not be presented as current defects or final implementation approval. A separate final independent red-team review is also reconciled below. Read-only reviews are advisory, not simulation or synthesis proof.

**Pre-RTL chair review (lightweight, not independent):**
- Advocate: the existing explicit-oldest interface already describes a contiguous K-row window; extending its physical ring earns the requested prefetch capacity without a new module or a pixel copy.
- Skeptic: adding banks alone is insufficient because the old code reads every bank, causing a same-bank collision even when writing a supposedly spare bank. Gate reads to active membership; do not confuse storage with readiness. Protect whole active rows rather than resurrecting destructive word refill.
- Evidence: inspected RTL has K physical banks, modulo-K output selection and an unconditional bank read enable. Small pre-change store/frontend baselines pass; the new interface test fails elaboration because SPARE_ROWS does not exist yet. No new behavior or physical result is established by that failure.
- Feasibility/alternative: fixed K+1 misses the requested parameter; a map/FSM solves a larger scheduling problem. A widened ring plus existing addresses is a reversible local change, but extra memory and selection area require real synthesis.

**Provisional chair verdict before RTL: proceed conditionally** with the contract and smallest standalone behavioral experiment, retaining caller-owned readiness and the accepted-read-only assertion limitation. Independent reports will be reconciled before final acceptance, not portrayed as received before they finish. Stop for any timing mismatch, active-row corruption or missing embedded memory.

### Returned initial council — reconciliation against the implementation

- **Advocate:** supports the contiguous K+SPARE_ROWS ring as the minimal extension, preserving K output pixels, vertical low-slice-oldest ordering and horizontal right-cache tap-zero-newest ordering. Adopted total-bank widths/parameter propagation, active-only reads, widened modulo arithmetic, caller-owned readiness and ordered promotion. No FIFO/controller, pixel copy or shift redesign was introduced.
- **Skeptic:** conditionally supports the architecture but warns about request-versus-registered selector skew, destructive-refill tests, inactive-cycle ownership and incomplete integration evidence. Current store read gating uses incoming `read_oldest_i`; output selection uses registered `oldest/lane`. Benches now use spare prefetch, retained-window replay, complete-path consumption and explicit consecutive accepted-read rotations. Bubble ownership and simulation-only guard limits remain explicit.
- **Evidence/feasibility:** the old tests and K-only resource figures were not sufficient proof. Adopted runner/synthesis parameter propagation, raw-image oracles, preserved whole-suite logs/configuration-specific manifests, S=2/3 and larger-spare cases, specific diagnostic guards/mutants and actual K+S RAM-node checks. The old 130-case report and old `latest.json` files are historical; current evidence is enumerated below, not inferred from the reviewers' earlier tool/version/hash observations.
- **Explicit contract choice:** the advocate allowed optionally retaining different-word active-bank writes under last-use safety. That suggestion was **not adopted**: the current contract preserves whole active rows and rejects any active-bank write during an accepted read, including a different word. Retaining destructive refill would defeat intact-window replay. This remains a simulation assertion, not synthesized request blocking or ownership enforcement.
- **Integration distinction:** complete-path frame traversal prefetches the next row during the preceding scan with no between-row repair load. The frontend bench separately tests delayed independent L/R completion before promotion; not every adversarial frontend row is claimed to finish prefetch within its scan.
- **Additional measured skeptic check:** a disposable mutant using registered `oldest` instead of incoming `read_oldest_i` for bank read gating compiles and fails the raw-pixel scoreboard on the first accepted column; the unmodified K=3/P=8/W=7/S=2 store passes. Evidence: `build/spare-row-request-gating-check/evidence.json`. This is one additional **ad-hoc** fault experiment, not a change from the standard checker's 38 registered mutants. Original code hashes match; the temporary script removed itself before tests.
- **Reconciled verdict:** the three initial reports support the chosen minimal architecture subject to the documented readiness/timing/evidence contract. Their old-baseline test gaps have been addressed as recorded, not reclassified as final RTL defects. The subsequent scoped independent review below found no concrete implemented RTL defect. No further RTL change follows from these late reports; no fitted timing, autonomous scheduler or board claim is added.

### Returned independent red-team and reconciliation

- The final independent review inspected the packed-store/frontend RTL, standalone store bench and frontend `read_row` only. Its conclusion was **conditional acceptance, no concrete RTL correctness defect**. This is a scoped independent source review, not a whole-system council verdict or independent rerun.
- Its W>1, W%4=1 partial right-row concern omitted the caller's completion step: `load_row()` fills any missing L/R word before `run_frame()` invokes `read_row()`. The scoreboard also rejects uninitialized reads. Fresh W=5/S=1, W=9/S=2 and W=5/S=6 frontend cases pass; no scheduler/RTL fix was needed.
- Accepted coverage suggestion: the store bench now preloads all spares and changes `read_oldest_i` on consecutive accepted reads, crossing the ring forward and backward with alternating x boundaries. A clocked consumer and raw-image oracle check payload/valid alignment; `adjacent_rotations` must equal `2*S`. This tests the store-port contract, not removal of frontend drain/clear requirements.
- Post-review **ad-hoc verification** passes 14 real-DUT cases, including K=1, one-bit/10-bit pixels, S=1/2/3/5, the full 480-row production-width store, W=5/9 frontend cases and S=6 frontend/complete-path cases. All 13 walkthrough mappings, 38 mutants and nine contract guards pass. Final code hashes match; RTL hashes remain unchanged from the synthesis checkpoint. Evidence/logs: `build/spare-row-audit-verification/evidence.json`.
- The OS-safe `verification-script-*` temporary harness was executed and removed. This is **not a fresh complete default-suite run or native Questa run**; the 142-case and native-compilation results below predate this testbench-only extension. No new fitting/board claim.

## Test-first acceptance

- Preserve pre-change source copies/hashes and passing small packed-store/frontend baselines under `build/spare-row-baseline/` (local artifacts only).
- Update standalone packed-store bench to prefetch into actual spares, replay all active pixels before swapping, fill every spare including narrow rows, and traverse repeated whole-ring wraps. The new test rejects the old interface at elaboration (missing SPARE_ROWS); that is a test-first failure, not a successful functional fault rejection.
- Frontend bench: independent L/R loads, delayed partial rows completed before promotion, simultaneous same-word-address reads/spare writes, exact tap/left/tag/consumer checks, clears and bubbles.
- Complete-path bench: load initial K rows only, prefetch every subsequent row during the previous scan, then consume it without between-row reload. Independent full raw-pixel K-by-K costs for every mature lane and exact winner/tag/record checks.
- Keep all original cases with S=1; add S=2/3 cases for all three packed suites and a `--spare-rows` runner override.
- Expected-failure guard tests require specific simulation diagnostics (not compile failure): zero spares, insufficient bank width, invalid bank/word/x and active-bank overwrite including wrapped membership and a different word.
- Mutants must compile and then fail actual behavioral/contract checks; add active-read-gating, total-bank-wrap and spare-parameter-propagation faults.
- Final gates: exact-source walkthroughs, complete default regression, fault sensitivity, and actual Quartus A&S for store/frontend/32-lane compute with current source hashes. Native Questa: compile/run if available without disturbing the user's existing session. No fitting, board, autonomous ownership or throughput claim.

## Executed results — functional and synthesis gates passed

Three functional RTL files changed: store plus parameter propagation through frontend/top. No new functional module, row copy, FIFO, controller or alignment/engine/reducer latency. Existing exact-source walkthroughs and hierarchy links are synchronized. No staging, commit or push.

### Actual checks

- `python scripts/check_walkthrough.py`: **13/13** source/walkthrough/registered-bench mappings pass.
- Before the audit-only store-bench extension, `python scripts/run_tests.py`: **142/142** cases pass, preserving the original 130 and adding 12 S=2/3 variants across packed store/frontend/complete datapath. Default stress is 2000 cycles; six legacy-reference cases retain 5000. Complete log: `build/spare-row-regression.txt`. Latest verification after that extension is the targeted ad-hoc run above, not a new whole-suite run.
- `python scripts/check_test_sensitivity.py`: **38 compiled mutants rejected**, plus **nine specific invalid-parameter/address/active-bank cases**. New mutants cover spare read gating, modulo-K instead of modulo-(K+S), missing spare storage and lost S propagation through either wrapper. Syntax failures and unrelated diagnostics are not counted.
- Extra seed `987654321`, 200-cycle stress: packed K=1/P=8/W=5/S=5; packed K=3/P=10/W=5/S=6; actual frontend and complete top K=3/P=10/W=5/T=3/S=6 all pass. This includes more spares than K and rows narrow enough to require paused prefetch completion. Log: `build/spare-row-extras.txt`; frontend VCD also recorded.
- Changed Python scripts compile with `py_compile`; scoped `git diff --check` passes. Whole-worktree checking reports pre-existing trailing whitespace in unrelated `Accelerator/Engine/Column Sum Buffer - Code Walkthrough.md:386`, which was left untouched.
- Initial checkpoint: `build/verify_spare_final.py` re-read actual manifests, checked RTL hashes against all synthesis/native-compilation inputs and reran source/mutation/guard checks. Output: `build/spare-row-final-verification.txt`; checkpoint hashes/paths/commands/results: `build/spare-row-final-evidence.json`. The store-bench hash in that checkpoint intentionally predates the audit-only extension; current code hashes are in the audit evidence above.

### Initial production-width examples (before audit-only bench extension)

| Case | Actual passing observations |
|---|---|
| Packed K=11/P=8/W=640/S=1 | 480 source rows, 470 windows, 469 complete future rows prefetched, 75,040 overlapping read/write beats, 469 same-word-address overlaps, 39 physical-ring wraps; complete active-window replay checked |
| Frontend K=11/P=8/W=640/T=32/S=1 | 41 rows, 23,737 accepted reads, 10,240 same-word-address prefetch overlaps; raw L/R payloads, all right taps/masks, tags and clears checked before/after edges |
| Complete path K=11/P=8/W=640/T=32/S=1 | 41-row selected frame plus directed/stress/restart phases; 23,936 winner outputs and 4,800 same-word-address prefetch overlaps. No between-row reload during selected-frame traversal; every mature candidate and winner/record checked against full raw windows |

These are **functional test counts, not achieved FPGA throughput**. Wide standalone storage retains 480 rows; production-width frontend/compute uses 41 rows at S=1 and 44 at S=2. Backend-only remains 38 rows. The earlier K=3/W=64 full-height compute run is historical, not a fresh full-height spare-row run.

### Fresh Quartus Lite 22.1 Analysis & Synthesis

Actual functional tops, Cyclone IV E, K=11/P=8/W=640; T/LANES=32 where applicable. RAM Summary checks exactly K+S M9K nodes per image, rather than accepting a logic-only smoke implementation.

| Top | S | Logic elements | Registers | Logical memory bits | M9K nodes | Errors / warnings |
|---|---:|---:|---:|---:|---:|---|
| Packed store | 1 | 632 | 8 | 61,440 | 12 | 0 / 1 |
| Stereo frontend | 1 | 4,264 | 2,985 | 122,880 | 24 | 0 / 1 |
| Complete 32-lane datapath | 1 | 30,274 | 15,519 | 122,880 | 24 | 0 / 2 |
| Packed store | 2 | 1,091 | 8 | 66,560 | 13 | 0 / 1 |

Common warning: one configured processor versus available processors; the top additionally warns about deliberately zero record-padding pins. These are synthesis utilization, **not fitted area/timing**. S=2 store synthesis confirms the parameter is not only a simulation alternative. S=2/3/5/6 integration is functionally simulated; only S=1 frontend/complete-top synthesis ran here.

Use `python scripts/check_row_buffer_synthesis.py --top <packed|frontend|datapath> --quartus-map <installed-quartus_map>`, adding `--spare-rows 2` for the additional store run. The final manifest records exact project paths, commands, warnings and source hashes for all four builds.

### Native simulator and acceptance boundaries

Before the audit-only store-bench extension, native Questa dependency/store/frontend/datapath/guard compilation passed with **zero errors and zero warnings**. S=2 runtimes for store, frontend and complete path all failed license checkout because the user's existing node-locked session was already running. It was not closed/killed. The updated store bench has not been freshly compiled with native Questa. No native simulation pass is claimed: current functional results are **Icarus**. Logs/manifest: `build/spare-row-native/`.

- The parameter adds capacity, not arbitrary load bandwidth or scheduling. Both complete L/R future rows must be ready before promotion; caller preserves active rows even during bubbles/row-clear.
- Simulation assertions reject writes to active banks during accepted reads, including different-word and wrapped cases. With no ownership state, they do **not** police active-bank writes during read-invalid bubbles; caller protocol still applies.
- No fitted timing, SDRAM/Avalon/Nios V, autonomous controller, board success or measured 32-lane throughput claim.
- Pre-RTL chair review was lightweight as recorded above. All three initial proposal reviews and the scoped final red-team review have now returned and been reconciled above; distinguish proposal support from independent review of final source, and neither from executed verification.
- Functional/synthesis evidence and targeted audit follow-up support conditional acceptance under the caller-owned readiness contract; user module-by-module review remains open. **Uncommitted and unpublished.**
