# Stereo frontend

[[Accelerator Architecture]] → [[Stereo Frontend Blocks.canvas|frontend schematic]]. Row-buffer, right-column-cache and left-delay RTL exist. [[Column Pairing Verification]] checks the delay/cache locally; row-buffer/engine assembly and the canvas's full wiring remain planned.

- [[Image Line Buffers]] — raster-to-column role.
- [[Circular Row Buffer]] — RTL walkthrough and standalone testbench.
- [[Right Column Shift Register]] — implemented right taps and per-tap validity.
- [[Left Column Delay]] — matching registered left payload/valid.
- [[Hands-on Testbench Lab]] — build and understand standalone benches before wrapper integration.
- [[Disparity Bank]] — planned right taps and left fan-out.
