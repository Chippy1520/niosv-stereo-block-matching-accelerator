# Accelerator architecture

[[System Architecture]] → [[Accelerator Blocks.canvas|accelerator schematic]]. [[Stereo SAD Datapath]] composes the complete compute path; transport and controllers remain **planned**, not implemented RTL.

- [[Stereo Frontend]] — two vertical row buffers, left broadcast and direct right disparity taps.
- [[Stereo SAD Datapath]] → [[Stereo Frontend]] + [[SAD Search Backend]] — packed loads through tagged minimum-cost/disparity output; no controller/FIFO/backpressure.
- [[Right Column Shift Register]] + [[Left Column Delay]] — tested standalone and in [[Column Pairing Verification]], then reused by the complete compute path.
- [[SAD Engine Architecture]] — one engine and its calculator/history.
- [[SAD Search Backend]] → [[Single SAD Engine]] + [[Minimum Comparator Tree]] — full fixed search, prefix warmup, common-interior masking and wall-clock tag alignment.
- [[Minimum Comparator Tree]] → [[Minimum Comparator Tree - Code Walkthrough]] — independently verified reducer, reused inside the backend.
- [[Timing and Pipelining]] — alignment and drain/clear timing.
- [[Verification Map]] — current evidence and benches.
- [[Datapath Study Guide]] — one connected course through every implemented module, its exact-code note, state, widths, edge timing and independent test design; planned integration remains explicitly separate.
