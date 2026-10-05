# Verification map

[[Home]] → [[System Architecture]] → [[Accelerator Architecture]] → [[Stereo Frontend]] / [[SAD Engine Architecture]].

- [[Verification]] — observed evidence and limits.
- [[Testbench Guide]] — independently scored RTL benches.
- [[Circular Row Buffer]], [[Pipelined Column SAD Calculator]], [[Column Sum Buffer - Code Walkthrough]], [[Single SAD Engine]] and [[Minimum Comparator Tree - Code Walkthrough]] each embed a source walkthrough and have a standalone self-checking bench.
- [[Right Column Shift Register]] — exact RTL, independent accepted-column indexing, per-tap validity and component synthesis.
- Future RTL follows `AGENTS.md`: source + code-adjacent walkthrough + bench in the same milestone, checked in CI.
