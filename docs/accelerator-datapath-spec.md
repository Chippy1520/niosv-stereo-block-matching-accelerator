# Accelerator compute datapath — design specification and execution ledger

[[Project Plan]] · [[Accelerator Architecture]] · [[Verification]]

## Authorization and finish line

The user requests completion of all compute-datapath components, council-evaluated decisions before implementation, an explanation after each component, then an interactive module-by-module simplification review **before any commit or push**. This supersedes the earlier stop-after-frontend boundary and per-block approval pause for implementation. It does not authorize controllers or board/transport implementation. Testbenches supply scheduling.

Finish line: independent packed L/R loads → stored vertical columns → disparity-aligned columns → parallel K×K SADs → minimum valid SAD/disparity → tagged 32-bit result. Preserve the existing serial lessons and unrelated staged/user changes.

## Frozen decision — independent council reconciled before RTL

Objective: complete the arithmetic path with the fewest meaningful, independently testable boundaries. Alternatives: (A) one monolithic top containing bank/reducer logic; (B) one cohesive SAD search backend plus a packed-load top composing it with the frontend; (C) separate one-lane wrapper, lane bank, reducer wrapper, packer and top. Choose B: backend owns engines, alignment/masking, minimum selection and final tag delay; top owns composition with row storage. Avoid C's forwarding-only modules. Existing single-engine module already covers the one-lane arithmetic boundary. Time-multiplexing is a real alternative only if measured resources demand it; it needs replay/scheduling and is not implemented here.

Council: independent advocate, skeptic and combined evidence/feasibility auditor reviewed the same neutral draft and actual interfaces without seeing each other's conclusions. All conditionally supported B; the chair accepts the RTL-derived boundary/timing arguments, not a vote count. The skeptic's severe per-lane-hole objection changes the frozen protocol below; all-lanes qualification prevents partial-search leakage. Cheap acceptance gate: backend K=3/three lanes and K=1/one lane with independent raw-pixel windows, exact edge/tag checks, ties, bubbles and aborts before packed-top integration. Confidence: high on partition/timing; physical feasibility remains conditional on integrated A&S, with no fitted timing claim. Reviewers ran no simulation/synthesis; their reports are advisory, not implementation verification.

Decisive criteria: independently checked raw-pixel results, exact metadata/valid timing, K=1 and odd lane counts, row-end/abort behavior, preserved embedded RAM, explanation clarity and measured resource feasibility. No new FIFO, ownership engine, FSM, transport or runtime configuration. Council verdict must be recorded before new functional RTL.

## Proposed interfaces and decisions

### `sad_search_backend`

Parameters: K=11, PIXEL_W=8, LANES=32, IMG_W=640, IMG_H=480; derived SAD/coordinate/disparity widths. One clock, synchronous active-low reset, synchronous clear. Inputs: `valid_i`, one K-pixel left column, LANES K-pixel right columns, LANES right-valid bits, x/y and row_last. Inputs already correspond to the same left coordinate.

Each generated lane d is an existing `sad_engine`, accepting `valid_i && right_valid_i[d]`; it must receive its early real columns to warm its own horizontal history. Lane d means disparity d, fixed at elaboration. Do not gate engine input until the common interior.

Single-pass search only: LANES equals the entire compile-time disparity count. No lane reuse/group-base/replay or cross-group winner merge. Smaller parameter builds search a smaller range, not the same 32 disparities with claimed speedup.

Common valid output interior: x >= K+LANES-2 and y >= K-1. Emit no padded or partial-search borders. Keep invalid candidates out of the minimum, preserve lower-disparity ties, feed one existing comparator tree. All output candidates must refer to the same input coordinate. Pipeline tags in wall-clock edges (including bubbles), not accepted-beat counts. A clear aborts engines, reducer and tags together.

Outputs: result valid, unsigned SAD, disparity, matching x/y and row_last. No ready/backpressure; the consumer must sample every valid output. No FIFO required until transport is designed.

### `stereo_sad_datapath`

Packed-load/read/clear inputs match `stereo_frontend`, including independent L/R write enables/data but shared write bank/word addresses. Current `SPARE_ROWS=1` (minimum one) propagates into both stores; BANK_W covers K+SPARE_ROWS physical banks. Compose that frontend with the backend; no duplicated arithmetic, cache, RAM or coordinate counters. The [spare-row increment](verification/spare-row-prefetch.md) supersedes K-only destructive refill, not arithmetic timing.

Output exposes valid, SAD/disparity, x/y/row_last plus a 32-bit record. Record bit 31 is valid, low SAD_W bits hold SAD, next D_W bits hold disparity, intervening bits are zero; require SAD_W+D_W <=31. On invalid cycles record is zero. Coordinates remain explicit sidebands; they cannot be squeezed into the same record without changing its contract. This is an internal datapath result interface, not a 32-bit physical board pinout or SDRAM protocol.

### Caller protocol and row boundaries

Rows begin at x=0, accepted x increments by exactly one, y/oldest bank stay fixed within a row; bubbles do not advance history. On every accepted backend beat, right_valid_i[d] must equal (x>=d): prefix warmup only, no independent mid-row lane holes. Simulation assertions reject violations rather than promising gap recovery. Every reduction is enabled only when all engines are valid for the common-interior beat; a missing lane cannot become a partial-search winner. Coordinates are bottom-right/trailing left-window anchors; disparity d pairs R[x-d], and row_last_o is qualified by result valid (empty interiors have none). Initialize both complete K-row windows and preserve every active row throughout the scan, including bubbles. Prefetch only into spare banks; same-word-address reads/writes in different banks are legal because spare banks do not read. Promote only after both complete L/R rows are ready, advancing oldest modulo K+SPARE_ROWS at the drained/cleared boundary; retired oldest becomes spare without copying. This is caller scheduling, not a synthesized readiness/ownership manager. Packed words remain low-slice-first, with padding never read as a real pixel.

Row clear preserves stored RAM and may permit loads, but resets horizontal histories and tags. Frame clear rejects loads/reads and aborts visibility; it does not erase RAM. Normal row end drains the frontend handoff, engine latency and reducer/tag pipeline before a separate clear edge. Abort clear may discard pending results; no completion pulse or autonomous drain timer is implemented.

## Verification contract

## Frozen timing/feasibility contract

Let L=ceil(log2(K)), E=L+1, R=max(1,ceil(log2(LANES))). An input-column beat sampled by the backend at edge t produces engine SADs after t+E. The comparator samples them at t+E+1 and produces its winner after t+E+R. Backend metadata therefore uses indices 0..E+R (the index-zero register samples at t); a result tag must not be advanced only on valid beats. With the frontend, a packed read sampled at t reaches the backend at t+2, so final output is after t+2+E+R. The downstream consumer sees it at the next edge. Normal row clear occurs on a separate edge after this final result can be sampled.

For K=11/P=8/LANES=32: E=5, R=5, backend offset=10 and packed-read-to-result offset=12 edges. SAD_W=15, D_W=5, maximum cost=30,855; record bits [14:0]=SAD, [19:15]=disparity, [30:20]=0, [31]=valid. First common x=41. A fully verified 640×480 frame would emit 281,530 records; this is an expected-count calculation, not a measured throughput or a test result.

The separate existing frontend/single-engine synthesis results do not establish complete-bank fit/timing. Synthesize the actual composed 32-lane top; do not claim a result from multiplying module area. Smaller lane-count parameter sweeps change search range and cannot be presented as same-work speedup. Public widths must match the derived sufficient minima; the top's 32-bit record constraint is an elaboration-time limit, not silent truncation.

The test-only shared raw-image oracle is deliberately outside RTL and is shared by the backend and packed-top standalone benches. It computes each complete K×K candidate once, then pipelines expected results/candidate vectors for checking; it never reproduces DUT running-sum, eviction, ring rotation or cache state.

### Required verification cases

Backend standalone: direct independent raw-image K×K sums for every lane and winner, no rolling-SAD model; exact cycle/tag/count checks, one/odd/32 lanes, K=1, non-power-of-two K, insufficient width/height, ties, nonzero winning disparities, extreme contrast, bubbles, outstanding-work clear/reset and row_last. Top standalone: drive real packed row loads through both stores, run multiple rows/bank wraps, independent L/R enables, retained RAM across row clears, raw-image oracle and exact 32-bit packing.

New RTL ships with standalone registered benches, exact first SystemVerilog walkthrough blocks and code-adjacent explanations, hierarchy links and mutation checks. Verify backend before full path. Run all regressions, walkthrough check, fault sensitivity and available Quartus Analysis & Synthesis. Include production K=11/P=8/W=640/LANES=32 and odd width/lane cases. Full-height frontend/frame evidence must be labeled honestly. No fitted Fmax, backpressure safety, controllers, board success or measured throughput claim from simulation/A&S.

## Milestones / live ledger

- [x] Inspect existing frontend, engine, comparator, runner and exact-source checker.
- [x] Reconcile independent council; freeze timing/ports and implementation decisions.
- [x] Implement and verify backend; explain purpose, connections and abstract mechanism.
- [x] Implement and verify complete packed-load top; explain purpose, connections and abstract mechanism.
- [x] Complete the original K-only compute regressions/mutations/synthesis and hierarchy/evidence. Spare-row verification is recorded separately.
- [ ] Interactive review and simplification of all modules before publication.

Current state: both compute modules and their real raw-window benches are implemented; [the original compute report](verification/compute-datapath.md) preserves the K-only verification. The user's current spare-row request changes packed storage/parameter propagation and its tests; [the current ledger](verification/spare-row-prefetch.md) records review, actual runs and limits. Interactive simplification review remains open; no staging, reset, commit or push is authorized for this increment.
