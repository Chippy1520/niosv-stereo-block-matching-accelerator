# Image Line Buffers
#planned

The first piece is implemented as [[Circular Row Buffer]]: one image stream, a ring of K rows, and one vertical column out.

Still not implemented: wiring two synchronized instances to a stereo frontend, a **right-column shift cache** after the right row buffer, one-cycle matching delay for the left column, fixed disparity taps, border masks, and the controller that drains [[Single SAD Engine]] after `row_last_o`. See [[Module Blocks.canvas]] for the compact top-level flow and [[Stereo Frontend Blocks.canvas]] for the grouped frontend inputs, outputs, and tap explanation.

Proposed flow: paired pixels → two [[Circular Row Buffer]] instances → right K-pixel-column shift cache (`Q[d]=R[x-d]`) and matching left-column delay → 32 tap/lane pairs (`L[x], Q[d]`) → replicated [[Single SAD Engine]] instances → [[Minimum Comparator Tree]]. The row buffers keep their K-row history across output-row boundaries; clear the cache and engine histories **after** draining, not the row buffers. Each right tap must be invalid until its x coordinate exists.
For now assume rectified images; calibration/rectification is upstream.
