# Accelerator architecture

[[System Architecture]] → [[Accelerator Blocks.canvas|accelerator schematic]]. The full transport/controller/bank is **planned**, not implemented RTL.

- [[Stereo Frontend]] — two vertical row buffers, left broadcast and direct right disparity taps.
- [[Right Column Shift Register]] + [[Left Column Delay]] — tested standalone and in [[Column Pairing Verification]]; complete frontend/engine hookup remains planned.
- [[SAD Engine Architecture]] — one engine and its calculator/history.
- [[Disparity Bank]] — parallel disparity lanes and validity.
- [[Minimum Comparator Tree]] → [[Minimum Comparator Tree - Code Walkthrough]] — standalone candidate-reduction RTL; bank hookup remains planned.
- [[Timing and Pipelining]] — alignment and drain/clear timing.
- [[Verification Map]] — current evidence and benches.
