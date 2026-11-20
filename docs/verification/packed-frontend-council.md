# Packed frontend — module-boundary and mux-order review

> Earlier K-only checkpoint review. [The spare-row ledger](spare-row-prefetch.md) records the current change and its distinct review provenance; earlier approval is not an independent audit of new RTL.

[[Stereo Frontend]] · [[Packed Circular Row Buffer]] · [[Row Word Bank]] · [[Project Plan]]

## Scope and review provenance

The initial sections below record a **lightweight main-agent review**, completed while independent findings were pending. Three read-only independent reviewers—advocate, skeptic, and evidence/feasibility auditor—have since returned. Their findings and caveats are reconciled below. All conditionally favor the current boundaries; this is not a proof of an optimal partition or an independent audit of the later final-source revision. The first draft preceded the user's mid-task council request; structural work was paused for review. The local mux change was assessed and measured without adding a module or changing interfaces.

## Neutral decision

- **Decision:** keep the current small boundaries and simplify selection within the packed row store, or change module partitioning/add buffering now?
- **Objective:** a readable, directly testable datapath that accepts four-pixel words independently of column reads and infers embedded memory. Not maximum module count, theoretical elegance or an unproven claim of optimality.
- **Alternatives:** retain the draft word-first mux; select one pixel per bank before rotating rows; fold the word RAM into the store; merge storage/alignment into one monolith; or retain the serial baseline and put an unpacking FIFO ahead of it.
- **Constraints:** no FIFO, ownership/refill FSM or central controller; no copies between row banks; direct tests before integration; exact-source walkthroughs; no publication before user review.
- **Decisive criteria:** functional timing/packing equivalence, embedded RAM inference, comprehensibility and measured rather than speculative resource cost.
- **Reversibility:** mux order is local and reversible. Port contracts and module boundaries need not change.

## Advocate

**Conditional support:** keep one actual RAM primitive, one cohesive packed row-store datapath, and the stereo frontend that wires two stores into existing alignment/cache blocks. The RAM boundary is substantive: it isolates the physical word-memory contract and inference pattern. The row store owns word/pixel selection and row ordering, while the frontend owns the paired alignment and tags. These are independently useful test boundaries, not forwarding-only wrappers. Pixel-first selection preserves behavior and narrows the subsequent cross-bank rotation from whole words to pixels.

**Risk:** extra module boundaries can be taught as unnecessary layers; public derived-width parameters are not intended as runtime configuration. Each boundary must continue to earn its place through a distinct contract/test.

## Skeptic / red team

**Case against the draft:** rotating full 32-bit words before discarding three pixels unnecessarily widens the expensive selection network. Retaining old and new storage files is also a potential maintenance/teaching trap. There is no evidence that a FIFO would solve a present datapath requirement, and it would introduce capacity, ownership and reset work.

**Genuine strength:** the current boundaries are shallow and actual memory/data contracts, not a generic transport framework. Folding the RAM into the store is a valid alternative but does not inherently remove hardware; a large combined module would obscure the RAM-inference and independent load/read contract.

**Guardrail:** label the old serial modules as separate reference lessons. They are not instantiated in the packed frontend. Do not add a fourth forwarding/adapter layer or a scheduler to make the demo autonomous.

## Evidence auditor

Direct tool evidence before adopting the simplification:

- Draft default regression: **110 simulation cases passed**. The standalone packed stores cover 640×480/641×480 images; full-width K=11 frontend cases use 38 rows, not 480.
- Targeted sensitivity: **26/26 faults detected**, with compilation errors excluded as evidence.
- Draft packed store: **2,633 LE, 8 registers, 56,320 logical memory bits and 11 M9K RAM nodes** at K=11/P=8/W=640.
- Isolated pixel-first experiment: **879 LE, 8 registers, the same memory bits and 11 M9K nodes**. Its K=11/P=8/W=9 raw-image bench passed.
- Draft full frontend: **8,061 LE, 2,985 registers and 112,640 memory bits**, Analysis & Synthesis successful.
- All new sources/benches compiled natively in Questa; runtime was rejected by the existing node-locked user session. No native runtime pass is claimed and that session is untouched.

The experiment supports a narrower mux network, not universal optimality, fitted timing or a final frontend resource figure. Final-source regression, fault sensitivity and production-width synthesis must be rerun after adoption. Reproducible commands/evidence are recorded separately in `docs/verification/packed-frontend.md`.

## Feasibility / alternatives

No new dependency, memory copy, module or pipeline register is required. The cheap discriminating experiment already reduces packed-store logic by **66.6%** while retaining embedded memory. A FIFO/serial unpacker would defeat direct word loading; a monolith would reduce file count but not necessarily hardware or learning complexity. Unifying the old and new RAM primitives would require reconciling different read/write collision contracts and is not necessary for this increment.

The caller/testbench must still enforce initialized reads, safe row/word lifetime, no same-word dual-port collision, ordered per-row processing and correct drain/clear sequencing. No claim of safe autonomous operation follows from datapath tests.

## Independent findings and reconciliation

The read-only fan-out was dispatched at 16:11:39 and completed after approximately two minutes. Its reports inspect the **earlier draft**, before the final measured mux simplification; earlier counts/timeouts are observations of that draft, not contradictory claims about the final revision.

| Finding | Independent position | Current reconciliation |
|---|---|---|
| Boundaries | Advocate, skeptic and auditor conditionally retain word bank → packed store → stereo frontend. RAM inference, spatial selection and stereo pairing are distinct useful contracts. | Retained. No FIFO, forwarding layer, extra pipeline stage or controller added. Packed inlining is not proved impossible; it lacks a measured benefit here. |
| Mux order | All recommend testing lane-before-bank selection; none claims unmeasured savings or timing improvement. | Later isolated and final-source checks measure 2,633→879 LE for the store, 8,061→4,546 LE for the frontend, preserving RAM/registers/latency. This is parent-verified evidence, not a result independently rerun by reviewers. |
| Walkthrough registration | Advocate encountered malformed `.sv`-suffixed entries; the auditor's later short check passed. | Registration was repaired during the work. Subsequent checks pass all 11 source/bench mappings, including the fresh focused ad-hoc run. |
| Frontend timeout/coverage | Earlier log stopped after six small cases. Auditor explicitly identified H=38, not H=480, in the wide case. | Subsequent full-width/T32 runs finish. Documentation now distinguishes the 38-row frontend test from standalone 480-row store scans. Full-height frontend simulation remains unverified. |
| Coordinate protocol | Skeptic notes that merely increasing x is insufficient for accepted-beat disparity history. | Contract/walkthrough now require x=0 then contiguous accepted x, constant y/oldest within a row, and inter-row history clear. Current RTL does not detect protocol violations; future controller assertions/integration tests remain necessary. |
| Load independence and ownership | Shared write bank/word addresses are not independent L/R addresses. All banks read on every request; different-word overlap alone does not prove safe overwrite. | Documented explicitly. Caller serializes differently addressed L/R arrivals and preserves initialized data through its final required read. No ownership proof/controller is claimed. |
| Clear/parameters | Pending handoff is discarded by clear; y range and overridden Y_W sufficiency are not checked. | Keep drain versus abort distinct. These remain caller/configuration obligations, not silently added hardware guarantees. |

The independent reports do not demonstrate fitted timing, a complete frontend frame, autonomous safe scheduling, a 32-engine bank or board operation. Their conditional agreement supports the present boundary choice; it does not remove these limits.

## Chair's verdict

**Retain the measured pixel-first implementation and the three current boundaries, conditionally supported by the independent draft reviews and subsequent parent-run verification.** Keep the RAM primitive for its memory-inference contract, related mux/tag logic inside the row store, and paired alignment/tags inside the frontend. Add no FIFO, controller or forwarding wrapper. The independent findings are reconciled above rather than treated as votes or as final-revision verification. Protocol assertions and whole-frontend/controller integration remain future gates.

**Confidence:** high in the local algebraic simplification and measured store-area advantage; moderate in long-term module partitioning. Fitted timing, whole-accelerator area and downstream engine-bank integration are not established. Stop for user review before another datapath block or publication.
