# Verification map

[[Home]] → [[System Architecture]] → [[Accelerator Architecture]] → [[Stereo Frontend]] / [[SAD Engine Architecture]].

- [[Verification]] — observed evidence and limits.
- [[Integration Readiness]] — current packed-compute readiness, caller obligations and remaining controller/platform gates; links the archived serial-stage audit separately.
- [[Testbench Guide]] — independently scored RTL benches.
- [[Control Emulation]] — real packed-load-to-winner integration under a test-only frame scheduler, independent L/R completion gates, retained-bank ownership, drain/clear and a clocked output sink; deliberately unsafe schedules must fail.
- [[Circular Row Buffer]], [[Pipelined Column SAD Calculator]], [[Column Sum Buffer - Code Walkthrough]], [[Single SAD Engine]] and [[Minimum Comparator Tree - Code Walkthrough]] each embed a source walkthrough and have a standalone self-checking bench.
- [[Row RAM Bank]] is independently tested before its serial reference parent. Its production-width mapping and 640×480 stream tests are measured; see [[docs/verification/row-buffer-synthesis|serial-storage evidence]]. It is not extra RAM in the packed path. Interactive datapath review precedes publishing; controller last.
- [[Right Column Shift Register]] — exact RTL, independent accepted-column indexing, per-tap validity and component synthesis.
- [[Left Column Delay]] — exact RTL, before/after-edge checks and component synthesis.
- [[Column Pairing Verification]] — local delay/cache integration, not a complete frontend.
- [[Row Word Bank]] → [[Packed Circular Row Buffer]] → [[Stereo Frontend - Code Walkthrough]] — independently tested word RAM/store, then two-store alignment/cache/tag interconnection. Direct packed loads, no FIFO/controller. [[Stereo Frontend]] is the hub; engines remain outside this frontend.
- [[Hands-on Testbench Lab]] — practical bench-writing route and individually exercised modules.
- [[SAD Search Backend]] → [[Stereo SAD Datapath]] — direct-column backend first, then real packed-load composition. Both use independent complete raw-pixel windows; expected values never read DUT history. Candidate outputs are observed only for comparison. See [[docs/verification/compute-datapath|compute-path evidence]].
- [Current spare-row verification](../docs/verification/spare-row-prefetch.md) — same-word-address spare writes, intact active-window replay, multiple spares, no-copy wraps and real shift/SAD integration; caller-owned complete-row readiness.
- [[Datapath Study Guide]] — module-by-module implementation and test contracts, independent references and runnable seven-module worked examples.
- Future RTL follows `AGENTS.md`: source + code-adjacent walkthrough + bench in the same milestone, checked in CI.
