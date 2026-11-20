# Integration Readiness

[[Verification]] · [[Verification Map]] · [[Project Plan]] · [[Datapath Study Guide]]

## Verdict

**The packed-load compute datapath is implemented and tested; the complete board system is not.** [[Control Emulation]] adds a simulation-only caller to test loading, readiness, bank reuse, drain/clear and result consumption together. It does not add controller RTL or replace interactive datapath review. Publication of the current snapshot is now user-authorized; hardware control remains a separate future milestone.

This is the **current readiness index**, not a new tool-run report. The [publication-time verification](../docs/verification/github-snapshot.md) records the latest reruns. Earlier configurations, source fingerprints, case counts, warnings and the distinction between full-regression and later ad-hoc checks remain in [[docs/verification/spare-row-prefetch|the spare-row evidence ledger]]. The original [[Paper Design Plan.canvas|accelerator paper plan]] and [[Paper System Plan.canvas|system paper plan]] remain intended architecture, not proof of system integration.

## Implemented compute path

- [[Stereo Frontend]] owns two [[Packed Circular Row Buffer|packed stores]], the [[Left Column Delay|left delay]], [[Right Column Shift Register|right disparity cache]] and aligned `(x,y,row_last)` tags.
- [[SAD Search Backend]] owns the fixed-disparity engine bank, common-interior qualification, [[Minimum Comparator Tree|minimum reducer]] and matching winner tags. Each [[Single SAD Engine]] contains its own calculator and column-cost history.
- [[Stereo SAD Datapath]] composes the actual frontend and backend through tagged winners and the 32-bit record. The serial [[Circular Row Buffer]] / [[Row RAM Bank]] remain separate reference lessons, not additional storage in this path.

```text
independent L/R packed loads → K+SPARE_ROWS stores → aligned L[x] / R[x-d]
→ per-disparity SAD engines → minimum reducer → tagged winner / 32-bit record
```

No autonomous scheduler, ownership tracker, FIFO, backpressure or memory transport is present. Independent writes share bank/word address ports; readiness is not inferred merely from allocated spare RAM.

## Readiness by layer

| Layer | Current status | Remaining gate |
|---|---|---|
| Functional module delivery | Exact-source explanations and standalone registered benches exist. | Preserve source/bench/walkthrough parity; tests are not exhaustive proof. |
| Packed frontend | Implemented; raw-image store, column, tap and tag checks exist. | Caller maintains initialized active rows across bubbles and complete L/R future-row readiness. |
| Fixed-search backend and complete compute path | Implemented; independent full raw-window candidate/winner scoreboards exist. | Interactive simplification review; autonomous control remains separate. |
| Spare-row headroom | Parameterized active/spare ring; no-copy promotion and intact-window replay tested. | Ordered successor must be ready before advancing oldest; assertions are not synthesized ownership protection. |
| Resource mapping | Production-width packed store, frontend and complete top have real Quartus Analysis & Synthesis evidence. | Fitting, clock/I/O constraints and TimeQuest timing; pre-fit resources are not achieved throughput. |
| Autonomous row/frame controller | **Not implemented.** [[Control Emulation]] exercises a test-only scheduler and independent protocol monitor around the real top. | Review and implement hardware separately; simulation stimulus is not a synthesized controller. Stop safely even for rows without winners. |
| Smaller-bank replay and cross-group best merge | **Not implemented.** | A smaller lane count does not already search a larger fixed range. |
| Stalled-output handling and transport | **Not implemented.** | Define actual accepted-transfer, buffering/reservation and completion requirements before adding elasticity. |
| Nios V/SDRAM/CSRs and board system | **Not implemented here.** | Platform proof, transport protocol checks, cache ownership, fitting and repeated frame comparison. |

## Contracts to review, not reinvent

- [[docs/packed-frontend-contract|Packed frontend contract]] — lane packing, shared load addresses, active-bank lifetime, independent L/R completion and registered handoffs.
- [[docs/accelerator-datapath-spec|Compute specification]] — bottom-right coordinates, common interior, prefix warmup, lower-disparity ties, record packing and wall-clock tags.
- [[Timing and Pipelining]] · [[Stereo SAD Datapath]] — drain the complete path, then clear on a **separate edge**. Reset/abort is not a normal row drain.

## Evidence boundaries and next work

Current functional evidence uses Icarus. Native Questa source/bench compilation passed, but the recorded fresh simulation attempts were blocked by the user's existing node-locked session; that session was left running. No new native runtime, fitted timing or board result is implied by tidying these notes.

The earlier serial-stage audit, native simulation table and historical interface discussion are preserved in [[Integration Audit - Serial Baseline|the archived serial-baseline audit]]. Earlier packed K-only and compute checkpoints are labelled historical in [[Verification]].

Resume the [[Project Plan#Next steps and acceptance gates|current review route]]. Platform proof can proceed in parallel: Nios V → intended SDRAM region → CSR → stalled pass-through transport. The system definition of done still requires comparable lane-count builds, measured timing/resources/throughput and repeated frame batches under a shared memory boundary; see [[docs/design_hierarchy|the system-design report]].
