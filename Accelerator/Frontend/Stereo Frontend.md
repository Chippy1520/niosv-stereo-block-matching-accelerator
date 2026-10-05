# Stereo frontend

[[Accelerator Architecture]] → [[Stereo Frontend Blocks.canvas|frontend schematic]]. Single-stream row-buffer and standalone right-column-cache RTL exist; stereo pairing and the canvas's assembly wiring remain planned.

- [[Image Line Buffers]] — raster-to-column role.
- [[Circular Row Buffer]] — RTL walkthrough and standalone testbench.
- [[Right Column Shift Register]] — implemented right taps and per-tap validity; matching left alignment remains next.
- [[Disparity Bank]] — planned right taps and left fan-out.
