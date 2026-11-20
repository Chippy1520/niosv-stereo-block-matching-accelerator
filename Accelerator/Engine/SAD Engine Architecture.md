# SAD engine architecture

[[Accelerator Architecture]] → [[SAD Engine Blocks.canvas|one-engine schematic]]. [[SAD Search Backend]] reuses this implemented engine in its fixed-disparity bank and reducer hookup. The calculator/history below are children of each engine, not extra parallel stages outside it.

- [[Single SAD Engine]] — wrapper RTL walkthrough and testbench.
- [[Pipelined Column SAD Calculator]] — pixel differences and reduction RTL walkthrough.
- [[Column Sum Buffer - Code Walkthrough]] — rolling horizontal cost RTL walkthrough.
- [[Column Sum Buffer]] — buffer overview.
- [[Rolling SAD Math]] — arithmetic intuition.
- [[Verification Map]] — benches and evidence.
