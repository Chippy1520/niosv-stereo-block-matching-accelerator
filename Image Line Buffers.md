# Image Line Buffers
#planned

The first piece is implemented as [[Circular Row Buffer]]: one image stream, a ring of K rows, and one vertical column out.

Still not implemented: a second instance wired to the engine, disparity shift, border policy, and the controller that drains [[Single SAD Engine]] after `row_last_o`. See [[Module Blocks.canvas]] for that split.

Flow: [[Nios V Interface]] → [[Circular Row Buffer]] → disparity tap (planned) → [[Column SAD Engines]].
For now assume rectified images; calibration/rectification is upstream.
